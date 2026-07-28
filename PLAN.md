# Implementation plan

## Milestones

### Milestone 1 — fixture-driven vertical slice — **complete**

A whole journey that works with no camera, no network and no credentials.

| Piece | Where | State |
| --- | --- | --- |
| Home screen, one dominant action | `App/Views/RootView.swift` | done |
| Fixture capture picker | `App/Views/ScanFlowView.swift` | done |
| Six recognition fixtures incl. malformed | `Recognition/RecognitionFixtures.swift` | done |
| Strict Codable contract, defensive decode | `Recognition/RecognitionContract.swift` | done |
| Repair once, then fall back to typing | `Recognition/RecognitionClient.swift` | done |
| Information precedence | `Facts/FactResolver.swift` | done |
| Deterministic warnings | `Rules/GERDRulesEngine.swift` | done |
| ≤ 2 clarification questions | `Rules/ClarificationPlanner.swift` | done |
| One-tap logging | `Flow/ScanFlowModel.swift` | done |
| SwiftData persistence | `Persistence/` | done |
| Window coalescing, one check-in | `CheckIn/MealWindowPlanner.swift` | done |
| Local notification scheduling | `App/Services/` | done |
| In-app "bring the check-in forward" | `AppEnvironment.simulateDueCheckIn()` | done |
| Severity + optional symptoms | `App/Views/CheckInView.swift` | done |
| Urgent-symptom advisory | `Safety/UrgentCarePolicy.swift` | done |
| History + meal detail | `App/Views/HistoryView.swift` | done |
| Conservative insights | `Insights/InsightEngine.swift` | done |
| Share-sheet export (text + CSV) | `Export/ReportExporter.swift` | done |
| Accessibility, Dynamic Type | throughout | done |

### Phase 2 — real integrations — not started

Ordered by how much each one improves the thing for its actual user, cheapest
first. Each sits behind a boundary that already exists, so none of them should
require touching the rules engine.

1. **Real capture.** Camera + photo library behind `CaptureService`. Highest
   value: without it she cannot use the app at all.
2. **VisionKit barcode and label scanning** behind `BarcodeAndTextScanner`.
   Unlocks the specificity that packaged food should have.
3. **Open Food Facts** behind `ProductLookupClient`. Turns a barcode into real
   ingredients rather than a guess.
4. **A real recognition provider** behind `RecognitionClient`. Needs a
   credential; see `Secrets.xcconfig.example`, and read the note there about the
   proxy before this leaves one phone.
5. **Longer-range insights.**
6. **Optional HealthKit investigation.**
7. **On-device recognition experiments.**

## Risks

| Risk | Why it matters | What was done |
| --- | --- | --- |
| A model invents medical advice | Direct harm to the person using it | Warnings come only from a deterministic rules engine; the provider returns bytes, is told not to advise, and its output is never rendered as guidance |
| Overconfident wording creeps in | Turns an observation into a claim | `SafetyWording` runs as a test over every rule, warning, insight and question |
| A confident-sounding guess overrides something known | Wrong note shown as fact | `FactResolver` precedence, tested in both input orders |
| Malformed provider output crashes or half-populates | Dead end mid-flow | Bounded, sanitising decoder; one repair; then typing a name |
| Notification permission refused | Check-ins silently never happen | Pending check-ins live in the database and show on the home screen regardless |
| Two meals close together nag twice | She stops using it | 90-minute eating window, one coalesced check-in, each meal still recorded |
| Small-sample insights read as findings | False confidence | Thresholds, raw counts always shown, percentages only at 10+, explicit "not enough information yet" |
| Photos accumulating on the phone | Privacy | Photos discarded after recognition; retention is explicit opt-in and unused in Milestone 1 |
| SwiftData schema fragility | Data loss between builds | Structured values stored as JSON blobs, windows joined by plain id; relaunch survival is tested against a real on-disk store |

## Verification

```sh
make test        # 111 core tests + 16 app tests + 4 UI tests
make build       # iPhone 16 simulator, Debug
```

Fresh results are in `RESULTS.md`.
