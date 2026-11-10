# Caro Styling

An iPhone app and its server: a styling studio for the clothes you already own. Read `docs/PRD.md` before any work. It is the source of truth for behaviour.

## Who you are working with

Marta is a designer and innovation lead who is learning to code. She built the Unspoken Diary (a web app in Express) with Claude Code. Swift, SwiftUI and Xcode are new to her.

- Before writing code for a ticket, explain the plan in plain language: which files, what each does, why.
- Prefer simple, readable code over clever code. Few dependencies. Ask before adding one and say why it is needed.
- After each ticket, tell her exactly how to test it: commands, what to press in Xcode, what she should see in the Simulator and on her iPhone.
- Explain new concepts briefly the first time they appear (SwiftUI views, state, the Keychain, Xcode targets, signing, API routes, migrations, environment variables, and so on).
- Keep answers short. Offer to go deeper instead of going deep by default.

## How we work

- One ticket at a time, from the build plan in `docs/PRD.md` section 17. Start each ticket in plan mode.
- Use Git. One branch and at least one commit per ticket, with a clear message. Do not push unless asked.
- Before calling a ticket done, run it and check it against its "Done when" and the matching screens.
- Do not start the next ticket until Marta says so.
- If a ticket shows the PRD is wrong or missing something, say so and propose the change to `docs/PRD.md`; do not silently build something else.

## Project layout

- `app/`: the iPhone app (Swift, SwiftUI, iOS 17 or later).
- `server/`: the server (Node, Express, SQLite).
- `docs/`: the PRD, the benchmark, and the spike results once T1 is done.
- `design/`: screens, tokens and assets from the design canvas.

## Design

- `design/screens/*.dc.html` are the reference screens, exported from the Caro Styling design canvas. Read them for exact spacing, sizes, colours and copy. They are written for a web canvas: rebuild them in SwiftUI, do not copy the HTML. `design/screens/README.md` maps each file to its screen and ticket.
- Tokens are in `design/tokens.json`. The wordmark is in `design/assets/`.
- Screens marked "to design" in the PRD's screen index follow the same style. Say what you added.
- Use native iOS behaviour (navigation, sheets, the system camera and photo picker, Dynamic Type) with Caro's look on top.
- Copy: use it as written. Sentence case. No em dashes, no emoji, no exclamation marks.

## Rules that must hold on the server

- Every request is scoped to the signed-in member. A member never reads or changes another member's data. The admin sees totals, never photos.
- Only invited, active emails can sign in. Codes are hashed, expire after 15 minutes, and allow 5 attempts.
- Photos are private, served only to their owner through signed-in requests. Strip location data before storing.
- The Claude API key lives only on the server, never in the app.
- There is no endpoint that generates or proposes looks. The AI recognises; it never styles.
- Store searches run only on an explicit request for one piece, only on the member's stores.
- The unlock rule is checked on the server. Once open, it stays open.
- Never log sign-in codes, session tokens or the API key in production.
