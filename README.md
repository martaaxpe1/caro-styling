# Caro Styling: from the design canvas to Claude Code

This folder is the handoff from design to build. It is also the start of the code repository: Claude Code will add the app (`app/`) and the server (`server/`) next to these files.

## How to run it

Both halves run on your Mac. Start the server first.

**The server**, in Terminal:

```bash
cd server
npm install           # first time only
cp .env.example .env  # first time only
npm run dev
```

It prints two addresses: one for the Simulator and the browser, one for your iPhone. Open `http://localhost:3000/health` in a browser to see `{"ok":true}`. It restarts by itself when a file changes. Stop it with Control C.

**The app**, in Xcode:

1. Open `app/Caro.xcodeproj`.
2. In the device menu at the top of the window, choose a simulator (iPhone 17) or your iPhone.
3. Press Run (Command R).

On your iPhone: same wifi as the Mac, phone unlocked. The first time, allow Caro to find devices on your local network. With a free Apple account, an app installed from Xcode stops opening after 7 days: press Run again.

## The database

One SQLite file, `server/data/caro.db`, ignored by Git. Its tables are built by the numbered files in `server/src/db/migrations/`, which run by themselves the first time the database is opened. To change a table later, add a new numbered file; never edit one that is already committed.

In `server/.env`, set `ADMIN_EMAIL` to your email first. Then, in `server/`:

```bash
npm run seed       # adds you as admin and a test invitation for sara@example.com, and prints both
npm run reset-dev  # deletes the local database and seeds a fresh one (never runs online)
npm run db         # opens the database in the Mac's sqlite3
```

In `sqlite3`: `.tables` lists the tables, `SELECT * FROM users;` shows a table (end each query with a semicolon), `.quit` leaves.

To pretend it is another day, put `DEV_TODAY=2026-10-30` in `server/.env`, or run one command with it: `DEV_TODAY=2026-10-30 npm run reset-dev`.

## What is in here

| Path | What it is | Who reads it |
|---|---|---|
| `app/` | The iPhone app: Swift and SwiftUI, opened with `app/Caro.xcodeproj`. | Both |
| `server/` | The server: Node, Express, SQLite. | Both |
| `CLAUDE.md` | Standing instructions for Claude Code: how we work, design rules, server rules. Read automatically at the start of every session. | Claude Code |
| `docs/PRD.md` | The spec (v1.2), with the build plan and tickets in section 17. | Both |
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
