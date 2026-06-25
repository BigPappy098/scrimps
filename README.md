# Theater Notes

Note taking for theater rehearsals and tech. Hold a walky-talky button, speak a
note, release. Each note is recorded, transcribed, and filed under the cast
member you addressed it to.

There are two versions in this repo:

- **`web/`** — a mobile-friendly **web app** (PWA). Runs in any browser on any
  device, installable to your home screen, works offline, no Mac required. See
  [`web/README.md`](web/README.md). This is the easiest way to use it anywhere.
- **iOS app** (this folder) — a native SwiftUI version. Docs below.

---

## iOS app

A native iOS app. Hold a walky-talky button, speak a note, release. The app
records each note, transcribes it on-device, and files it under the cast member
you addressed it to.

## How it works

1. **Cast tab** — add your cast (names + optional roles). These names are used as
   recognition hints so the speech engine spells them right, and to attribute
   each note to a person.
2. **Record tab** — give the session a title and tap **Start Show**. This copies
   the current cast into the session.
3. **Hold to Talk** — press and hold the big button, say your note, release.
   Start it with a name ("Sarah, your cross is late") to file it under that
   person; with no name it goes to **Everyone**. Keep pressing for each new note;
   they stream in and transcribe in the background.
4. **End Show** — finishes the session.
5. **History tab** — open any past show to read notes grouped by cast member,
   play back the original audio, fix a transcript, reassign a note to a different
   person, or share the whole set as text.

### Name matching

Each note's transcript is checked against the cast list. The first word(s) are
fuzzy-matched (so "Jon" still matches "John"), and on a match the name is
stripped from the note text and the note is filed under that person. No match →
the note is for everyone. You can always reassign in the History tab.

## Building & running on your phone

This is a native SwiftUI app, so it builds in **Xcode on a Mac**:

1. Open `TheaterNotes.xcodeproj` in Xcode 16 or newer.
2. Select the **TheaterNotes** target → **Signing & Capabilities** and set your
   **Team** (a free Apple ID works for running on your own device). Change the
   **Bundle Identifier** if `com.theaternotes.app` is taken.
3. Plug in your iPhone, pick it as the run destination, and press **Run** (⌘R).
4. First launch asks for **Microphone** and **Speech Recognition** permission —
   allow both.

> With a free Apple ID the app installs for 7 days before you need to rebuild it.
> A paid Apple Developer account ($99/yr) removes that limit and is required for
> TestFlight / App Store distribution.

## Notes & tech

- **Transcription:** Apple's `Speech` framework, on-device when supported — free,
  private, works offline. No API keys or accounts.
- **Audio:** AAC `.m4a` clips, one per note, stored per session in the app's
  Documents directory.
- **Storage:** sessions and cast are persisted to a JSON file; audio lives
  alongside it.
- **Minimum iOS:** 17.0.

### Possible next steps

- Optional OpenAI Whisper mode for higher accuracy on tough names.
- Categorize notes (blocking / lighting / sound / etc.).
- iCloud sync and PDF export.
