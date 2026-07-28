# Meal Notes — project guide

A private, camera-first food and drink journal for **one person**, built to help
her notice possible relationships between what she consumes and her GERD
symptoms. It is a personal observation tool. It is not a diagnostic or treatment
product, and nothing in it should ever imply otherwise.

Target: iPhone 16, iOS 18+, portrait, SwiftUI + SwiftData, no account, no
network, no analytics.

---

## Commands

Everything below assumes Xcode is not the active developer directory, which is
why `DEVELOPER_DIR` is set. The `Makefile` sets it for you.

```sh
make build       # build the app for the iPhone 16 simulator
make test        # everything: core package tests, then app + UI tests
make test-core   # fast inner loop — the pure logic (swift test, runs on macOS)
make test-app    # app unit tests and the UI test, on the simulator
make simulators  # what is actually available on this machine
```

Raw equivalents:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild -scheme MealNotes -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme MealNotes -destination 'platform=iOS Simulator,name=iPhone 16' test
cd Packages/MealNotesCore && swift test
```

**`xcodebuild` is the source of truth.** `swift test` covers the core package
only; it is fast and runs on macOS, but it does not build the app, so never
report the milestone as passing on its strength alone.

Do not assume a simulator name. Check with `make simulators` first. This machine
has an `iPhone 16` device created against the iOS 26.5 runtime; if it is missing:

```sh
xcrun simctl create "iPhone 16" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-16 \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
```

### Two test commands, not one

The core tests live in a Swift package and the app tests live in the Xcode
project. A hand-written `.xcscheme` does not reliably pick up a local package's
test target, so `make test` runs both rather than pretending one covers the
other. If the project is ever opened in Xcode, ticking `MealNotesCoreTests` in
the scheme editor will merge them.

---

## Layout

```
MealNotes.xcodeproj          hand-written, objectVersion 77, file-system-synchronised groups
App/                         the iOS app target — SwiftUI only
  MealNotesApp.swift         entry point; --uitest launches with a session-only store
  AppEnvironment.swift       dependency injection + observed home-screen state
  Flow/ScanFlowModel.swift   drives capture → questions → result → logged
  Services/                  UserNotifications-backed CheckInScheduler
  Views/                     presentation only
AppTests/                    app-level tests (Swift Testing) — the flow end to end
AppUITests/                  XCUITest — the one journey that matters
Packages/MealNotesCore/      all the logic, as a library
```

`Packages/MealNotesCore` is where nearly everything lives, and it must stay free
of SwiftUI and UIKit. That is not tidiness for its own sake: it is what lets the
rules engine, the recognition contract, the insight engine and the exporters be
tested as pure functions, on macOS, in under a second.

---

## Architecture

Views present. They do not capture, network, persist, schedule, or decide
anything medical. Every one of those lives behind a protocol:

| Boundary | Milestone 1 implementation | Phase 2 |
| --- | --- | --- |
| `CaptureService` | `FixtureCaptureService` | camera + photo library |
| `BarcodeAndTextScanner` | `FixtureBarcodeAndTextScanner` | VisionKit / Vision |
| `ProductLookupClient` | `UnavailableProductLookupClient` (returns `nil`) | Open Food Facts v3 |
| `RecognitionClient` | `MockRecognitionClient` (fixtures) | a real multimodal provider |
| `GERDRulesEngine` | **final** — deterministic, no substitute planned | — |
| `MealRepository` | `SwiftDataMealRepository` | — |
| `CheckInScheduler` | `UserNotificationsCheckInScheduler` (+ `InMemoryCheckInScheduler` for tests) | — |
| `InsightEngine` | counts over recorded observations | longer-range comparisons |
| `ReportExporter` | plain text + CSV | perhaps HTML/PDF |

### Data flow for one capture

```
CaptureService → BarcodeAndTextScanner → (ProductLookupClient)
      → RecognitionClient  ──bytes──▶  RecognitionResponseDecoder
      → FactResolver (precedence)      → GERDRulesEngine  → warnings + open questions
      → ClarificationPlanner (≤ 2)     → user answers become userCorrection facts
      → MealDraft → MealLogger → MealRepository + MealWindowPlanner + CheckInScheduler
```

`MealSnapshot` is the `Sendable` value type everything downstream of persistence
works on. SwiftData models never leave the repository.

### Concurrency

Swift 6 language mode, package and app. `MealRepository`, `MealLogger`,
`AppEnvironment` and `ScanFlowModel` are `@MainActor` because `ModelContext` is
not `Sendable`. Everything else is a `Sendable` value type or an actor.

---

## The safety contract

This is the part to be careful with. Read it before touching anything in
`Rules/` or `Safety/`.

1. **Only `GERDRulesEngine` decides that a note is shown.** A recognition
   provider can propose what a food *is*. It can never propose what that means.
   The provider is explicitly instructed not to give advice
   (`RecognitionRequest.defaultInstructions`), and its output is never rendered
   as guidance.

2. **The engine is a pure function.** Same facts in, same notes out. It has no
   access to history, no randomness, no I/O.

3. **A note requires a trusted-enough fact.** User corrections, label text and
   barcode records are taken as stated. A visual guess needs
   `FoodFact.warrantableVisualConfidence` (0.75) or better. Below that it becomes
   a *question*, never a note.

4. **Information precedence** (`FactResolver`):
   `userCorrection > labelText > barcodeDatabase > visualInference`.
   A lower-trust claim never displaces a higher-trust one. Within the same source
   and confidence, the *later* claim wins — that is what lets someone answer
   "yes" and then correct it to "no".

5. **At most two questions**, enforced twice: the decoder caps
   `clarifications` at `RecognitionLimits.maxClarificationQuestions`, and
   `ClarificationPlanner` caps again. A question is only asked when the answer
   would change what is shown; if the rule it would fire has already fired for
   another reason, it is skipped.

6. **Failure means silence, not invention.** If recognition fails, the fallback
   is typing a name and logging with no note at all. There is no code path that
   produces a warning from nothing.

7. **Every rule is traceable.** Stable versioned id, matchers, one reason, one
   suggestion, cited sources, evidence category, review date. Sources are limited
   to NIDDK and the ACG, and `RuleCatalogTests` enforces that.

8. **Dairy is deliberately unmatched.** `FoodCategory.dairy` fires nothing.
   Mainstream guidance points at *fat*, not dairy, so `fullFatDairy` is matched
   by `rule.highFat.v1` for its fat. `GERDRuleCatalog.intentionallyUnmatched`
   records the decision and a test enforces it. If an individual pattern shows up
   for this user it belongs in `InsightEngine`, as an observation.

9. **History is context, never authority.** `InsightEngine.personalNote` may add
   "You have recorded symptoms after caffeine twice before." It cannot change,
   soften or strengthen the baseline note.

10. **Correcting a logged meal does not rewrite what she was shown.**
    `applyCorrection` changes `displayName` and `facts` and appends to
    `corrections`; it leaves `shownRuleIDs` alone, because that records what was
    actually on screen at the time and a later correction does not make that
    untrue. The patterns *do* follow the correction, since `InsightEngine` counts
    facts rather than rule ids. `ScanToCheckInUITests` pins both halves.

### Wording

`SafetyWording.bannedPhrases` is enforced by tests over every rule string, every
rendered warning, every insight and every clarification question. Never say a
food is *safe, unsafe, good, bad, healthy* or *unhealthy*; never say something
*will cause*, is *guaranteed*, or is a *trigger*; never *diagnose*, *treat* or
mention *allergy* or *intolerance*. Matching is whole-word, so "food safety" is
fine and "this is safe" is not.

Warnings must never show a percentage or a risk score. Insights may show a
percentage only at 10+ observations, and always alongside the raw counts.

`AppDisclosures` and `UrgentCarePolicy` are exempt from the banned-word check —
they have to be able to say "medical care" and "speak to a doctor". Their copy is
tested separately for the opposite property: that it defers rather than triages.

### Result copy

```
Looks like: <name>

Heads up
<rule title>
<one short reason>
<one practical alternative>

[ I'm having this ]
```

At most two notes on screen (`GERDRulesEngine.maxDisplayedWarnings`). Any others
that fired are still recorded on the meal, but are not put in front of her.

### Urgent symptoms

Recording chest pain, difficulty or pain swallowing, vomiting blood, black or
bloody stool, persistent vomiting, or unexplained weight loss produces one flat
recommendation to seek care. The app does not rank them, estimate urgency, or
suggest a cause.

---

## Privacy constraints

- Everything is local. No account, no analytics, no advertising SDK, no
  third-party health-data sharing, no network calls at all in Milestone 1.
- **Photos are not stored.** A capture is held only long enough to identify it.
  `MealDraft.retainedPhotoData` is populated only when the user explicitly asks
  to keep one, and Milestone 1 never sets it.
- **A recognition request carries only the current image** plus a barcode and
  label text read on-device, and the minimum instructions. It structurally cannot
  carry meal history, symptom history, or anything about the person —
  `RecognitionPrivacyTests` asserts the exact field list of `RecognitionRequest`,
  so adding a field to that type fails the build's tests until it is justified.
- Stored: confirmed meals, corrections, recognition provenance and confidence,
  the rule ids that were shown, check-in answers, derived insight metadata.

---

## Testing

`Packages/MealNotesCore/Tests` (111 tests) covers rule matching, rule metadata,
the dairy nuance, information precedence, malformed and hostile recognition
payloads, the two-question cap, banned wording, window coalescing, SwiftData
persistence including survival across a store reopen, insight counts, and export
contents.

`AppTests` (16 tests) drives `ScanFlowModel` through every fixture.

`AppUITests` (4 tests) covers the required journey — scan → clarify → warning →
log → check-in → history — the unreadable-photo fallback, correcting an
ingredient before logging so the note it produced goes with it, and correcting a
meal *after* logging so the record of what was shown survives it.

When adding a rule, add a test for it. When changing copy, run `make test-core`;
the wording guardrail will tell you immediately.

---

## Conventions

- British-inflected, plain, unhurried copy. Short sentences. No exclamation
  marks. No cheerleading. She is an adult managing a condition, not a user being
  onboarded.
- Never rely on colour alone. Concern is carried by a heading, an icon *and*
  words.
- Minimum 44pt targets (`Layout.minimumTouchTarget`); the primary action is much
  larger. Full-row buttons instead of switches wherever a choice is being made.
- Support Dynamic Type at every size — no `.lineLimit(1)` on body copy, no fixed
  heights that clip.
- Every interactive element gets an `accessibilityIdentifier` in the form
  `screen.element`, so UI tests do not depend on visible strings.

---

## Milestone 1 — done

Home screen with one dominant action; fixture capture picker; six recognition
fixtures including a malformed one; ≤2 clarification questions; deterministic
warnings; one-tap logging; SwiftData persistence; window coalescing with a single
scheduled check-in; an in-app way to bring a check-in forward; severity and
optional symptom recording; history; a conservative insight; share-sheet export
as text or CSV; accessibility throughout. No network, no credentials.

## Phase 2 — proposed, not started

Keep these out of Milestone 1 code rather than half-wiring them.

1. **Real capture** — `AVFoundation` camera and `PhotosUI` picker behind
   `CaptureService`. The rest of the flow does not change.
2. **VisionKit barcode and label scanning** behind `BarcodeAndTextScanner`. Use
   `DataScannerViewController`; do not add a third-party scanner package unless a
   specific limitation is demonstrated.
3. **Open Food Facts lookup** behind `ProductLookupClient`. Small typed
   `URLSession` client, v3 product endpoint, descriptive User-Agent, local cache
   of successes, handling for rate limits, missing fields and unreliable
   community data. ODbL attribution goes in the app and in the export.
   Swift OpenAPI Generator only if the hand-written client becomes a burden, and
   then against a pinned local spec snapshot.
4. **A real multimodal recognition provider** behind `RecognitionClient`. The
   decoder, the repair-once behaviour and the manual fallback already exist and
   should not need changing. Add `Secrets.xcconfig` (untracked; see
   `Secrets.xcconfig.example`). An embedded key is acceptable **only** for a
   private prototype on one phone — put a small authenticated proxy in front of
   it before this goes anywhere else.
5. **Longer-range insights** — day-of-week, portion size, time since last meal.
   Raise the thresholds rather than lower them.
6. **Optional HealthKit investigation** — read-only, and only if it earns its
   privacy cost.
7. **On-device recognition experiments** — Core ML or MLX. Future work.
