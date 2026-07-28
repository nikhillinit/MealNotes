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

## `make test-app` — 18 tests

```
✔ Test run with 16 tests in 2 suites passed after 0.042 seconds.
Test Case '-[MealNotesUITests.ScanToCheckInUITests testScanClarifyWarnLogCheckInAndSeeHistory]' passed (35.590 seconds).
Test Case '-[MealNotesUITests.ScanToCheckInUITests testUnreadablePhotoFallsBackToTypingWithNoNote]' passed (17.334 seconds).
	 Executed 2 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

From the result bundle: `result: Passed | total: 18 passed: 18 failed: 0`.

> The `Executed 0 tests` lines in raw `xcodebuild` output are XCTest's counter,
> which does not count Swift Testing cases. The bundle summary is authoritative.

## `make build`

```
** BUILD SUCCEEDED **
```

Clean build of both the app and the package produces **no compiler warnings**
(the only line emitted is `appintentsmetadataprocessor … No AppIntents.framework
dependency found`, which is expected for an app that does not use App Intents).

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
