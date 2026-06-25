# Theater Notes — Web App

A mobile-friendly web version of Theater Notes. Push-to-talk note taking for
theater rehearsals and tech, runs in any modern browser, installable to your
home screen, works offline. No accounts, no server, no cost.

## Try it instantly

Open `web/index.html` in a browser, or serve the folder locally:

```bash
cd web
python3 -m http.server 8000
# then visit http://localhost:8000
```

> Speech recognition needs a **secure context**: `https://` or `localhost`.
> Plain `file://` won't get microphone access in most browsers.

## How it works

1. **Cast tab** — add cast names (+ optional roles). Used to match each note to a person.
2. **Record tab** — title the session, **Start Show**, then **hold** the big button,
   speak a note, release. Start with a name ("Sarah, your cross is late") to file
   it under that person; no name → **Everyone**. Notes stream in and transcribe as
   you go. **End Show** when done.
3. **History tab** — open any show: notes grouped by person, edit transcripts,
   reassign, delete, and **Share** (native share sheet on mobile, clipboard on desktop).

Names are fuzzy-matched (so "Jon" still matches "John") and stripped from the note text.
Everything is stored locally in your browser (localStorage).

## Browser support for speech

Uses the browser's built-in **Web Speech API**:

- ✅ **Chrome** (Android & desktop) — excellent.
- ✅ **Safari** (iOS & macOS) — works; needs internet and can be a little less
  reliable on long notes. Push-to-talk (short phrases) suits it well.
- ⚠️ Firefox — limited/no support; you'll see a notice.

If iPhone accuracy ever falls short, the app can be upgraded to a cloud Whisper
backend for top accuracy (needs a server + API key) — ask and it can be added.

## Install to your home screen (PWA)

- **iOS Safari:** Share → *Add to Home Screen*.
- **Android Chrome:** menu → *Install app* / *Add to Home Screen*.

It then launches full-screen like a native app and works offline.

## Deploying (GitHub Pages)

A workflow at `.github/workflows/deploy-pages.yml` publishes the `web/` folder.
To enable it: repo **Settings → Pages → Build and deployment → Source: GitHub
Actions**. After the next push the site goes live at the URL shown in the
workflow's summary.
