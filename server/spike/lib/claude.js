// The one place the spike talks to Claude. Every call goes through ask(), which
// times it, works out what it cost from the tokens used, and writes a line to the cost log.
//
// The API key is read from server/.env by Node (--env-file) and handed to the SDK.
// It is never printed or written anywhere.

const Anthropic = require('@anthropic-ai/sdk');
const { logCost } = require('./output');

// Prices in US dollars per million tokens, from Anthropic's pricing page on 2026-11-10.
// cacheWrite is the 5-minute cache. Haiku 5.5 costs more when one prompt is over 100,000 tokens.
const MODELS = {
  opus: {
    id: 'claude-opus-5-5',
    label: 'Opus 5.5',
    price: { input: 4, cacheWrite: 5, cacheRead: 0.2, output: 20 },
  },
  sonnet: {
    id: 'claude-sonnet-5-5',
    label: 'Sonnet 5.5',
    price: { input: 2, cacheWrite: 2.5, cacheRead: 0.1, output: 10 },
  },
  haiku: {
    id: 'claude-haiku-5-5',
    label: 'Haiku 5.5',
    price: { input: 0.1, cacheWrite: 0.125, cacheRead: 0.01, output: 0.5 },
    longPrompt: { over: 100000, price: { input: 0.5, cacheWrite: 0.625, cacheRead: 0.05, output: 2.5 } },
  },
};

const WEB_SEARCH_PRICE = 10 / 1000; // dollars per search
const PRICES_CHECKED = '2026-11-10';

let client = null;

// Stops the script with a clear message when the key is missing from server/.env.
function requireKey() {
  if (!process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_API_KEY.trim() === '') {
    console.error('No API key found.');
    console.error('Open server/.env and add a line: ANTHROPIC_API_KEY= followed by your key.');
    process.exit(1);
  }
}

function getClient() {
  requireKey();
  if (!client) client = new Anthropic();
  return client;
}

// "--model opus,haiku" becomes ['opus', 'haiku']. No option, or "all", means all three.
function pickModels(option, allowed = Object.keys(MODELS)) {
  if (!option || option === true || option === 'all') return allowed;
  const picked = String(option)
    .split(',')
    .map((name) => name.trim().toLowerCase());
  for (const name of picked) {
    if (!MODELS[name]) {
      console.error(`Unknown model "${name}". Use one or more of: ${Object.keys(MODELS).join(', ')}.`);
      process.exit(1);
    }
  }
  return picked;
}

function emptyUsage() {
  return { input: 0, cacheWrite: 0, cacheRead: 0, output: 0, thinking: 0, webSearches: 0, webFetches: 0 };
}

function addUsage(total, usage) {
  return {
    input: total.input + (usage.input_tokens || 0),
    cacheWrite: total.cacheWrite + (usage.cache_creation_input_tokens || 0),
    cacheRead: total.cacheRead + (usage.cache_read_input_tokens || 0),
    output: total.output + (usage.output_tokens || 0),
    thinking: total.thinking + ((usage.output_tokens_details && usage.output_tokens_details.thinking_tokens) || 0),
    webSearches: total.webSearches + ((usage.server_tool_use && usage.server_tool_use.web_search_requests) || 0),
    webFetches: total.webFetches + ((usage.server_tool_use && usage.server_tool_use.web_fetch_requests) || 0),
  };
}

function costOf(modelKey, usage) {
  const model = MODELS[modelKey];
  const promptTokens = usage.input + usage.cacheWrite + usage.cacheRead;
  const price = model.longPrompt && promptTokens > model.longPrompt.over ? model.longPrompt.price : model.price;
  const tokens =
    usage.input * price.input +
    usage.cacheWrite * price.cacheWrite +
    usage.cacheRead * price.cacheRead +
    usage.output * price.output;
  return tokens / 1e6 + usage.webSearches * WEB_SEARCH_PRICE;
}

// Structured output comes back as JSON in the last text block.
// With web search there can be text before it, so fall back to the last {...} in the answer.
function parseJson(content) {
  const texts = content.filter((block) => block.type === 'text').map((block) => block.text);
  const candidates = [texts[texts.length - 1], texts.join('')];
  for (const text of candidates) {
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
          // try the next candidate
        }
      }
    }
  }
  return null;
}

// Asks one model one question and returns what it said, with time and cost.
//   test, action: names for the cost log, like "1-details" and "piece details"
//   model: 'opus', 'sonnet' or 'haiku'
//   system: the standing instructions
//   content: the user message (text and image blocks)
//   schema: the form Claude fills in (JSON schema); leave out for a free text answer
//   effort: how much the model thinks before answering: 'low', 'medium' or 'high'
//   tools: server tools such as web search
async function ask({ test, action, model, system, content, schema, effort = 'medium', tools, note }) {
  const outputConfig = { effort };
  if (schema) outputConfig.format = { type: 'json_schema', schema };

  const messages = [{ role: 'user', content }];
  const request = {
    model: MODELS[model].id,
    max_tokens: 16000,
    system,
    messages,
    output_config: outputConfig,
  };
  if (tools) request.tools = tools;

  const started = Date.now();
  let usage = emptyUsage();
  let response;

  // A long web search turn can pause; sending it back lets the server carry on.
  for (let turn = 1; turn <= 5; turn++) {
    response = await getClient().messages.create(request);
    usage = addUsage(usage, response.usage);
    if (response.stop_reason !== 'pause_turn') break;
    messages.push({ role: 'assistant', content: response.content });
  }

  const seconds = (Date.now() - started) / 1000;
  const cost = costOf(model, usage);
  const refused = response.stop_reason === 'refusal';
  const refusalCategory = refused && response.stop_details ? response.stop_details.category : null;
  const data = refused ? null : parseJson(response.content);
  const text = response.content
    .filter((block) => block.type === 'text')
    .map((block) => block.text)
    .join('');

  logCost({
    test,
    action,
    model,
    effort,
    input_tokens: usage.input,
    cache_write_tokens: usage.cacheWrite,
    cache_read_tokens: usage.cacheRead,
    output_tokens: usage.output,
    thinking_tokens: usage.thinking,
    web_searches: usage.webSearches,
    web_fetches: usage.webFetches,
    seconds,
    cost,
    stop_reason: response.stop_reason,
    refusal_category: refusalCategory,
    note: note || null,
  });

  return {
    data,
    text,
    content: response.content,
    usage,
    cost,
    seconds,
    stopReason: response.stop_reason,
    refused,
    refusalCategory,
  };
}

// A short, readable version of an API error. A rejected key stops the script.
function describeError(error) {
  if (error instanceof Anthropic.AuthenticationError) {
    console.error('The API key was not accepted. Check the ANTHROPIC_API_KEY line in server/.env.');
    process.exit(1);
  }
  if (error instanceof Anthropic.APIError) {
    return `API error ${error.status}: ${error.message}`;
  }
  return error.message || String(error);
}

module.exports = {
  Anthropic,
  MODELS,
  WEB_SEARCH_PRICE,
  PRICES_CHECKED,
  requireKey,
  getClient,
  pickModels,
  costOf,
  ask,
  describeError,
};
