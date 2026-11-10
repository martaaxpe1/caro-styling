# Caro Styling: from the design canvas to Claude Code

This folder is the handoff from design to build. It is also the start of the code repository: Claude Code will add the app (`app/`) and the server (`server/`) next to these files.

## What is in here

| Path | What it is | Who reads it |
|---|---|---|
| `CLAUDE.md` | Standing instructions for Claude Code: how we work, design rules, server rules. Read automatically at the start of every session. | Claude Code |
| `docs/PRD.md` | The spec (v1.0), with the build plan and tickets in section 17. | Both |
| `docs/FIRST_PROMPT.md` | The first message to paste into Claude Code. | You |
| `docs/BENCHMARK.md` | The other wardrobe apps, and how Caro differs. | Both |
| `design/screens/` | The designed screens, exported from the canvas, plus a README mapping each to its ticket. | Claude Code |
| `design/tokens.json` | Colours, type, shapes and spacing of the Spread design. | Claude Code |
| `design/assets/` | The CARO wordmark. | Claude Code |
| `design/inspiration/` | Sara's original wordmark and palette. | Reference |

The design canvas stays the design source: https://claude.ai/artifact/2Z4LEXpkUS6eCRP6co1kkC

## Before you start

- **Xcode**, from the Mac App Store. Open it once so it installs its extra parts.
- **Node 22**, as for the diary.
- **An Anthropic API key**, for T1 (the AI spike). Keep it in `server/.env`, never in the app.
- Later, for T8: an **Apple Developer Program** membership (99 US dollars a year, for TestFlight), and accounts on **Resend** (email) and **Render** (hosting).

## The flow, step by step

1. **Open this folder in Claude Code.** In the Claude desktop app, Code tab, start a new session in `Wardrobe`.
2. **Switch to plan mode** before the first message.
3. **Paste `docs/FIRST_PROMPT.md`.** Claude Code reads everything, plays back what it understood, confirms the stack and plans T0.
4. **Review the plan.** Push back where it is unclear. When happy, say go.
5. **Test after every ticket.** Claude Code tells you how: usually run the server, press Run in Xcode, and check the iPhone Simulator. Some tickets also need your real iPhone.
6. **Ticket by ticket**, T0 to T11. One ticket per session keeps things clear. Start each one in plan mode.

## When the design changes

Change it on the canvas, then ask Claude to export the changed screens into `design/screens/` again, and tell Claude Code which screen changed.
