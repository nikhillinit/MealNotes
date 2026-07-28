# Meal Notes

A private food and drink journal for one person, built to help her notice
possible relationships between what she eats and her reflux symptoms.

Take a photo. See what it thinks it is. Get a short, calm note when there is
something worth mentioning. Tap once to log it. Answer one question a couple of
hours later. Look back at what actually happened.

It is a notebook, not medical care. It never labels a food, never claims one
thing caused another, and never shows a number pretending to be a risk.

## Running it

Needs Xcode 26 and an iPhone simulator.

```sh
make build   # build for the iPhone 16 simulator
make test    # run everything
```

Then open `MealNotes.xcodeproj` and run, or install to the simulator from the
command line. There is no account, no sign-in and no network call — the whole app
runs from fixtures in this first version, so it can be tried end to end on a
Mac with no camera.

To try the full loop in one sitting: scan an example photo, log it, then tap
**Bring my next check-in forward** on the home screen rather than waiting two
hours.

## Where things are

- `Packages/MealNotesCore` — all the logic: the recognition contract, the rules
  engine, persistence, insights, export. No SwiftUI, no UIKit, fast to test.
- `App` — the interface, and nothing else.
- `CLAUDE.md` — architecture, commands, the safety contract, privacy
  constraints, and what Phase 2 is.
- `PLAN.md` — milestones, risks, verification.
- `RESULTS.md` — the last verification run.

## Status

Milestone 1 is complete: the whole journey works from fixtures, with tests.
Real camera capture, barcode scanning, Open Food Facts and a real recognition
provider are Phase 2 and deliberately not started — see `CLAUDE.md`.
