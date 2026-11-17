---
name: screencast
description: Generate a narrated, subtitled screencast (MP4) of an approval-workbench workflow, driven by Selenium in Google Chrome with macOS text-to-speech. Use when the user asks for a screencast, demo video or recorded walkthrough of the app, e.g. "/screencast two approvers conflict on one invoice".
---

Generate a narrated Selenium screencast script for one approval-workbench workflow.

The arguments describe the workflow to record, for example:
- "two approvers decide the same invoice; the second gets a conflict"
- "requester creates a draft and submits it"
- "admin demotes an approver while the approval page is open"

## Files in this skill

- `lib.mjs`: everything shared. It covers narration audio (`say`, then `afconvert`), screen recording (`ffmpeg` avfoundation), browser helpers, sign-in and sign-out, an off-screen second user, subtitles and the final mix. A script only defines `STEPS` and calls `runScreencast`.
- `examples/approval_conflict.mjs`: the reference script. Follow its shape exactly.
- `package.json`: holds `selenium-webdriver`, installed into this skill's `node_modules` (git-ignored).

## What to do

0. **Check dependencies** before anything else:

   ```bash
   node --version
   ffmpeg -version 2>/dev/null | head -1; ffprobe -version 2>/dev/null | head -1
   ls .claude/skills/screencast/node_modules/selenium-webdriver/package.json
   ls "/Applications/Google Chrome.app"
   say -v '?' | grep -E '(Enhanced|Premium)' | grep 'en_'
   ```

   Stop with a clear message if any of these is missing:
   - **node**: `brew install node`.
   - **ffmpeg / ffprobe**: `brew install ffmpeg`.
   - **selenium-webdriver**: `npm install --prefix .claude/skills/screencast`.
   - **Google Chrome**: install it. Selenium Manager downloads the matching chromedriver on the first run, so that run needs network access.

   For the voice, `VOICE` defaults to `Samantha`. `say` silently falls back to the default voice for a name that isn't installed, so check with `say -v '?' | grep -F "<voice>"`; `runScreencast` also refuses an uninstalled voice. If an Enhanced or Premium English voice is installed, for example `Zoe (Premium)`, suggest running with `VOICE='Zoe (Premium)'`. These are downloaded in *System Settings → Accessibility → Spoken Content → System voice → Manage Voices*.

   Also tell the user that the terminal app that runs the script needs *Screen Recording* permission, in *System Settings → Privacy & Security*.

1. **Read `lib.mjs` and `examples/approval_conflict.mjs`** for the helpers and conventions.

2. **Understand the workflow** from the arguments. Read the routes, controllers and views it touches (`config/routes.rb`, `app/controllers/`, `app/views/invoices/`, `app/views/admin/`, `app/views/shared/`) to get exact selectors. Seeded accounts and data are in `db/seeds.rb`. The password comes from `DEMO_PASSWORD` (default `demo-password-2026`), and accounts are `requester@`, `approver1@`, `approver2@` and `admin@` at `acme.example.com` or `globex.example.com`.

3. **Generate `tmp/screencast_<slug>.mjs`**, a single file directly in `tmp/`, git-ignored:
   - Import helpers from `'../.claude/skills/screencast/lib.mjs'`.
   - Set `OUT_DIR = __dirname`, the `tmp/` folder. Audio is cached in `tmp/audio_<slug>/` and the video goes to `tmp/screencast_<slug>.mp4`.
   - `STEPS` is an array of `{ id, narration, actions: async (driver) => {} }` (one parameter per window). Each step's narration plays while its actions run.
   - The first step `01_intro` is narration only, plus `driver.get(`${BASE_URL}/session/new`)`.
   - The second step signs in with `signIn(driver, email)`. Switch users with `signOut` then `signIn`.
   - The last step is an outro with `sleep(8000)`.
   - End with `runScreencast({ slug, outDir: OUT_DIR, steps: STEPS })`.

4. **Action guidelines:**
   - Clicks always go through the helpers, so the viewer sees an orange ripple:
     - `click(driver, css)`;
     - `clickButton(driver, 'Approve')`, because this app's buttons have no ids;
     - `clickLink(driver, 'Audit history')`.
   - Fill text with `fill(driver, css, text)`. Choose from dropdowns with `selectByValue(driver, css, value)`, which shows the open option list.
   - Useful selectors:
     - sign-in fields: `#email_address` and `#password`;
     - status filter: `select[name="status"]`, then `clickButton(driver, 'Filter')`;
     - first row link: `table tbody tr:first-child td:first-child a`;
     - rejection reason: `textarea[name="transition[reason]"]`;
     - outcome notices: `#notice`.
   - After a form submit, wait with `await sleep(3000–4000)` rather than strict waits that can fail.
   - **Several users at once** (for example two approvers in a conflict): pass `windows: 2` (or more) to `runScreencast`. The windows split the recorded screen side by side, left to right, each a separate Chrome profile with its own sign-in. Every step's actions then receive them in that order, `actions: async (blair, alex) => {}`. Narrate which window to watch.
   - Pick records from the list, for example the first pending invoice, not by fixed name, so a re-run works on whatever data is left.

5. **Narration guidelines:**
   - Natural spoken English, without contractions that `say` mispronounces: "we will", not "we'll".
   - Each step says what the viewer sees and what happens next.
   - The sleeps inside a step must roughly match its narration length.
   - Refer to the seeded people by name (Alex, Blair, Rita, Ada), not by pronoun.
   - Never mention real people, companies or credentials. All data is synthetic.

6. **Output.** Give the file path and these commands to run in the user's own terminal (the script records the screen and plays audio, so it must not run inside Claude's tools):

   ```bash
   node tmp/screencast_<slug>.mjs
   ```

   Options:
   - `BASE_URL=https://workbench-bmwi.onrender.com` records against the hosted preview (open `/up` first to wake it).
   - `VOICE='Zoe (Premium)'` picks a voice.
   - `SCREEN=1` records the second display instead of the main one (0). The browser windows are placed on the recorded display automatically.

   Narration audio is cached per step, voice and text in `tmp/audio_<slug>/`, so edits regenerate only the changed clips.

   Warn that the script changes data, because decisions are real and audited and can't be undone. To re-run on fresh data, re-seed a disposable database: use `docker compose down -v && docker compose up --build` with `BASE_URL=http://127.0.0.1:3000`, or record against the hosted preview only once.
