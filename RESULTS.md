# Verification

Last run: 2026-07-28, on this machine.

## Environment

Discovered rather than assumed:

- Xcode 26.6 (build 17F113), at `/Applications/Xcode.app`.
  `xcode-select` still points at the Command Line Tools, so every command sets
  `DEVELOPER_DIR` — the `Makefile` does this for you.
- iOS 26.5 simulator runtime (installed via `xcodebuild -downloadPlatform iOS`).
- Simulator: `iPhone 16` (`B6AD4A29-081E-4A80-8050-F31A327C9819`), created with
  `xcrun simctl create` because the runtime ships iPhone 17 devices by default.
- Deployment target iOS 18.0, Swift 6 language mode, portrait, iPhone only.

## `make test-core` — 111 tests

```
✔ Suite "Clarification questions" passed
✔ Suite "Eating windows" passed
✔ Suite "GERD rule matching" passed
✔ Suite "Information precedence" passed
✔ Suite "Insights" passed
✔ Suite "Logging a meal schedules one check-in" passed
✔ Suite "Recognition coordination and failure handling" passed
✔ Suite "Recognition decoding" passed
✔ Suite "Recognition privacy" passed
✔ Suite "Report export" passed
✔ Suite "Rule catalog metadata" passed
✔ Suite "SwiftData persistence" passed
✔ Suite "Urgent symptoms" passed
✔ Suite "Wording guardrails" passed
✔ Test run with 111 tests in 14 suites passed after 0.052 seconds.
```

## `make test-app` — 19 tests

```
✔ Test run with 16 tests in 2 suites passed after 0.042 seconds.
Test Case '-[MealNotesUITests.ScanToCheckInUITests testCorrectingIngredientsRemovesTheNoteItProduced]' passed (18.305 seconds).
Test Case '-[MealNotesUITests.ScanToCheckInUITests testScanClarifyWarnLogCheckInAndSeeHistory]' passed (35.878 seconds).
Test Case '-[MealNotesUITests.ScanToCheckInUITests testUnreadablePhotoFallsBackToTypingWithNoNote]' passed (17.311 seconds).
** TEST SUCCEEDED **
```

From the result bundle: `passedTests: 19, failedTests: 0, skippedTests: 0`, on
`iPhone 16` / iOS 26.5 (`B6AD4A29-081E-4A80-8050-F31A327C9819`).

> The `Executed 0 tests` lines in raw `xcodebuild` output are XCTest's counter,
> which does not count Swift Testing cases. The bundle summary is authoritative.

## `make build`

```
** BUILD SUCCEEDED **
```

A clean build of the app, the package **and both test targets** produces **no
compiler warnings** (the only line emitted is `appintentsmetadataprocessor … No
AppIntents.framework dependency found`, which is expected for an app that does
not use App Intents).

`ScanToCheckInUITests` is `@MainActor` and uses the `async` `setUp`/`tearDown`
overrides rather than the `WithError` ones, which are nonisolated on
`XCTestCase`. Without both, Swift 6 warns on every `app.…` call.

## App icon

`AppIcon.appiconset` previously declared a 1024×1024 slot with no image, so the
app showed the default grey icon. It now has one, and it was checked by
installing rather than by trusting the build:

```sh
xcrun simctl install "iPhone 16" "$APP"
xcrun simctl launch "iPhone 16" com.apple.springboard
xcrun simctl io "iPhone 16" screenshot /tmp/shot.png
```

The compiled `AppIcon60x60@2x.png` in the bundle samples at exactly
`rgb(22, 83, 109)` — the app's `AccentColor`. On the home screen iOS 26 lays its
own depth shading over the artwork, so the rendered icon reads darker than the
source in places; that is the system treatment, not the asset. Regenerate with
`scripts/make_icon.py` if the artwork ever needs to change.

## Coverage against the brief's test list

| Required | Suite |
| --- | --- |
| GERD rule matching | GERD rule matching |
| Rule source metadata | Rule catalog metadata |
| Dairy and high-fat-dairy nuance | GERD rule matching |
| No-warning behaviour when recognition fails | Recognition coordination and failure handling |
| Information-precedence rules | Information precedence |
| Malformed recognition responses | Recognition decoding |
| Maximum clarification-question count | Recognition decoding, Clarification questions |
| Banned or overconfident wording | Wording guardrails |
| Meal-window notification coalescing | Eating windows, Logging a meal schedules one check-in |
| SwiftData persistence | SwiftData persistence (incl. survival across a store reopen) |
| Insight observation counts | Insights |
| Export contents | Report export |
| UI: scan → clarify → warning → log → check-in → history | `ScanToCheckInUITests` |

## Not verified

- Never run on physical hardware. Everything above is the iPhone 16 simulator.
- Notification *delivery* is not tested end to end — `MealLogger`'s scheduling is
  tested against `InMemoryCheckInScheduler`, and the real
  `UserNotificationsCheckInScheduler` is exercised only by running the app.
- VoiceOver was not driven programmatically. Identifiers, labels, traits,
  combined rows and 44pt minimums are implemented and visible in code, but no
  automated audit was run.
