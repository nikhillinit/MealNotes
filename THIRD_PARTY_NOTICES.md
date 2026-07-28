# Third-party notices

## Current state

**Meal Notes has no third-party dependencies.** No Swift packages are linked
apart from the app's own local `MealNotesCore`, no code has been copied in from
elsewhere, and no external dataset is bundled.

Everything is built on frameworks that ship with the platform:

| Framework | Used for |
| --- | --- |
| SwiftUI | the entire interface |
| SwiftData | local persistence |
| UserNotifications | the later check-in reminder |
| UIKit | `UIActivityViewController` for the share sheet |
| OSLog | diagnostics |
| Foundation | everything else |

`Vision`, `VisionKit`, `AVFoundation` and `PhotosUI` are named in the Phase 2
plan and are not yet linked.

`scripts/make_icon.py` uses Pillow to draw the app icon. That is a tool for
regenerating a checked-in asset, not a dependency of the app: nothing links it,
nothing ships it, and neither the build nor the test run needs Python.

## Guidance the warnings are based on

The app's rules do not copy text from these sources. They paraphrase widely
published patient guidance, and each rule links to where it came from so the
wording can be checked. Cited in `Packages/MealNotesCore/Sources/MealNotesCore/Rules/GERDRuleCatalog.swift`:

- **National Institute of Diabetes and Digestive and Kidney Diseases (NIDDK) —
  Eating, Diet, & Nutrition for GER & GERD.**
  <https://www.niddk.nih.gov/health-information/digestive-diseases/acid-reflux-ger-gerd-adults/eating-diet-nutrition>
  NIDDK content is a work of the U.S. federal government and is in the public
  domain. NIDDK does not endorse this app.

- **National Institute of Diabetes and Digestive and Kidney Diseases (NIDDK) —
  Symptoms & Causes of GER & GERD.**
  <https://www.niddk.nih.gov/health-information/digestive-diseases/acid-reflux-ger-gerd-adults/symptoms-causes>

- **American College of Gastroenterology — Acid Reflux.**
  <https://gi.org/topics/acid-reflux/>
  Referenced for orientation only; no ACG text is reproduced. The ACG does not
  endorse this app.

## Attribution owed in Phase 2

### Open Food Facts

If and when `ProductLookupClient` is backed by Open Food Facts, this section must
be updated before that code ships, and the attribution must also appear in the
app and in the exported report:

> Product data from **Open Food Facts**, made available under the
> **Open Database License (ODbL) v1.0**.
> <https://opendatacommons.org/licenses/odbl/1-0/> — <https://world.openfoodfacts.org>

Practical obligations that come with it:

- Credit Open Food Facts wherever product data is shown.
- Keep the data under the ODbL if any derived database is redistributed.
- Send a descriptive `User-Agent` identifying this app and a contact address, as
  their API terms ask.
- Treat the data as community-entered: fields are often missing and sometimes
  wrong. It ranks below label text and below anything the user confirms — see
  the precedence rules in `CLAUDE.md`.

### A recognition provider

If a hosted multimodal model is introduced, record here: the provider, the model,
the terms the account is under, and whether the provider may retain or train on
submitted images. That last point is a privacy decision about her photographs,
not a procurement detail, and it belongs in writing.

## Adding anything

Before adding a dependency, show that the platform framework cannot do the job.
When one is added, record here: what it is, why the native implementation was not
enough, its licence, and any attribution the licence requires. License automation
can wait until there are enough dependencies to justify it — right now there are
none.
