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

## Signing in

Caro is invite only: you sign in with your email and a 6-digit code. On this Mac no emails are sent. Sign-in codes and invitations are printed in the terminal where `npm run dev` runs, between two dashed lines.

1. In `server/`: `npm run reset-dev`, then `npm run dev`.
2. In the app, type the email from `ADMIN_EMAIL`, press **Send code**, and type the code from the terminal.
3. The profile button (your initial, top left) opens settings: **Admin** to add people, resend or cancel invitations, remove and restore access. **Sign out** is there too.

The app keeps you signed in (in the iPhone Keychain) until you sign out. After `npm run reset-dev` it asks you to sign in again, because the old session is gone.

```bash
npm run clean-up   # the daily clean-up, by hand: expires old invitations, deletes members removed over 30 days ago
npm test           # checks sign in and the admin area on a throwaway database; caro.db is not touched
```

The server runs the clean-up by itself when it starts and every 24 hours. To see what it would do 31 days from now: `DEV_TODAY=2026-12-15 npm run clean-up`.

## Onboarding and settings (T4)

A new member goes through five steps: welcome and name, where you live, your year, your stores, occasions. The app remembers the furthest step reached, so closing it and opening it again returns to the same step. Settings (the profile button) repeats the five steps.

To try it as the test Sara, with a pretend date so the "Now:" line reads hot and rainy:

1. In `server/.env`, add `DEV_TODAY=2026-10-30`. Stop `npm run dev` (Control C) and start it again, so it reads the new line.
2. If Sara has already signed in before, `npm run reset-dev` gives a fresh invitation for sara@example.com (it deletes your local database).
3. In the app, sign in as sara@example.com with the code from the terminal.

Two steps ask Claude, using the key in `server/.env`:
- **Your year** asks for a city's typical weather the first time anyone chooses that city (less than a cent), checks it against Open-Meteo, and keeps it in the `city_weather` table.
- **Your stores** looks up each store's website for your country when you press return (about 2 cents, a few seconds).

Each call is counted in the `ai_usage` table, which the admin area shows as "AI actions this month". `npm test` replaces both with fakes, so it costs nothing.

For testing against a second copy of the server (another port and database), a debug build can be launched with `-serverURL http://localhost:3100`, as an argument in Xcode (Product, Scheme, Edit Scheme, Run, Arguments) or with `xcrun simctl launch`. Without it, the app uses port 3000 as before.

## Online (T8)

The server runs on Render (render.com), set up by `render.yaml`: one web service in Frankfurt with a 5 GB disk at `/var/data` for the database, photos and backups. Its address is https, so the app talks to it securely without any exception.

- **Secrets** (`ANTHROPIC_API_KEY`, `ADMIN_EMAIL`, `RESEND_API_KEY`, `EMAIL_FROM`) live only in Render, under the service's Environment. Never in Git.
- **Deploy:** Render deploys from GitHub. Commit, push to `main`, then in Render press Manual Deploy, Deploy latest commit. Each deploy restarts the server; the disk keeps the data.
- **First time only:** in Render's Shell tab, `npm run seed` makes you the admin online.
- **Emails** go through Resend from the domain in `EMAIL_FROM`. On your Mac they still print in the terminal.
- **Backups:** online, the server zips the database and every photo once a day into `/var/data/backups/`, keeping the last 3. In Render's Shell, `ls -lh /var/data/backups` lists them, and `npm run backup` makes one now. Render also snapshots the whole disk every day. On your Mac, `npm run backup` makes one in `server/data/backups/` by hand.
- **Your data:** in the app, Settings has Download everything (a zip of your data and photos) and Delete account.

The app finds the server in `app/Caro/Config/AppConfig.swift`: builds run from Xcode use your Mac, TestFlight builds use Render. To run from Xcode against Render, add the argument `-serverURL https://caro-styling.onrender.com` (Product, Scheme, Edit Scheme, Run, Arguments).

## What is in here

| Path | What it is | Who reads it |
|---|---|---|
| `app/` | The iPhone app: Swift and SwiftUI, opened with `app/Caro.xcodeproj`. | Both |
| `server/` | The server: Node, Express, SQLite. | Both |
| `CLAUDE.md` | Standing instructions for Claude Code: how we work, design rules, server rules. Read automatically at the start of every session. | Claude Code |
| `render.yaml` | How Render sets up the online server. | Render |
| `docs/PRD.md` | The spec, with the build plan and tickets in section 17. | Both |
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
