// The one place the server talks to Claude (PRD section 10). Adapted from the T1 spike
// (server/spike/lib/claude.js), without the cost log.
//
// The API key is read from server/.env by Node and handed to the SDK. It never leaves the
// server, and it is never printed or logged.
//
// Every answer is a form Claude fills in (a JSON schema), so the server gets facts it can
// check, never free text. The AI recognises and looks things up; it never styles.

const Anthropic = require('@anthropic-ai/sdk');
const db = require('../db');
const { now, iso } = require('./today');

// The models chosen in the spike (docs/SPIKE.md): Sonnet for anything it must remember or
// see, Haiku for anything it must search the web for.
const MODELS = {
  sonnet: 'claude-sonnet-5-5',
  haiku: 'claude-haiku-5-5',
};

// A member waits for these answers, so a call gets 60 seconds and one retry at most.
const TIMEOUT_MS = 60 * 1000;

// Something went wrong asking Claude. The message is safe to show in the app.
class ClaudeError extends Error {}

let client = null;

function getClient() {
  if (!(process.env.ANTHROPIC_API_KEY || '').trim()) {
    throw new ClaudeError('The Claude API key is missing on the server.');
  }
  if (!client) client = new Anthropic({ timeout: TIMEOUT_MS, maxRetries: 1 });
  return client;
}

// The filled-in form comes back as JSON in the last text block. With web search there can
// be text before it, so fall back to the last {...} in the answer.
function parseJson(content) {
  const texts = content.filter((block) => block.type === 'text').map((block) => block.text);
  for (const text of [texts[texts.length - 1], texts.join('')]) {
    if (!text) continue;
    try {
      return JSON.parse(text);
    } catch {
      const start = text.indexOf('{');
      const end = text.lastIndexOf('}');
      if (start !== -1 && end > start) {
        try {
          return JSON.parse(text.slice(start, end + 1));
        } catch {
          // try the next one
        }
      }
    }
  }
  return null;
}

// Asks one question and returns the filled-in form.
//   model: 'sonnet' or 'haiku'
//   system: the standing instructions; prompt: the question, as text or as blocks (a photo and text)
//   schema: the form to fill in
//   tools: server tools, like web search, that run on Anthropic's side
//   effort: how much the model thinks first; low was enough in the spike
async function ask({ model, system, prompt, schema, tools, effort = 'low' }) {
  const messages = [{ role: 'user', content: prompt }];
  const request = {
    model: MODELS[model],
    max_tokens: 16000,
    system,
    messages,
    output_config: { effort, format: { type: 'json_schema', schema } },
  };
  if (tools) request.tools = tools;

  // Sonnet: if it ever declines (it never did in the spike), Anthropic answers the same
  // request with another model inside the same call, so the member still gets an answer.
  // Haiku has no such fallback.
  const withFallback = model === 'sonnet';
  if (withFallback) {
    request.betas = ['server-side-fallback-2026-07-01'];
    request.fallbacks = 'default';
  }

  let response;
  try {
    // A long web search can pause; sending the answer so far back lets it carry on.
    for (let turn = 1; turn <= 5; turn++) {
      response = withFallback ? await getClient().beta.messages.create(request) : await getClient().messages.create(request);
      if (response.stop_reason !== 'pause_turn') break;
      messages.push({ role: 'assistant', content: response.content });
    }
  } catch (error) {
    throw new ClaudeError(describe(error));
  }

  if (response.stop_reason === 'refusal') {
    throw new ClaudeError('Claude declined to answer.');
  }
  const data = response.stop_reason === 'end_turn' ? parseJson(response.content) : null;
  if (!data) {
    throw new ClaudeError(`Claude did not fill in the answer (${response.stop_reason}).`);
  }
  return data;
}

// A short description for the server's terminal. Never includes the key.
function describe(error) {
  if (error instanceof ClaudeError) return error.message;
  if (error instanceof Anthropic.AuthenticationError) return 'The Claude API key was not accepted.';
  if (error instanceof Anthropic.RateLimitError) return 'Claude is busy (rate limit).';
  if (error instanceof Anthropic.APIConnectionTimeoutError) return 'Claude took too long to answer.';
  if (error instanceof Anthropic.APIConnectionError) return 'Claude could not be reached.';
  if (error instanceof Anthropic.APIError) return `Claude answered with error ${error.status}.`;
  return error.message || String(error);
}

// One row per AI call, so the admin sees the totals and T11 can enforce the monthly allowance.
// action is one of the names in the ai_usage table: 'your year', 'store website', ...
function recordAiAction(userId, action) {
  db.prepare('INSERT INTO ai_usage (user_id, action, created_at) VALUES (?, ?, ?)').run(userId, action, iso(now()));
}

module.exports = { MODELS, ClaudeError, ask, recordAiAction };
