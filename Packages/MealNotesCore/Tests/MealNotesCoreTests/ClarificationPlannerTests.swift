import Foundation
import Testing
@testable import MealNotesCore

@Suite("Clarification questions")
struct ClarificationPlannerTests {
    let engine = GERDRulesEngine()

    @Test("Nothing unconfirmed means nothing is asked")
    func noQuestionsWhenNothingIsUnclear() {
        let evaluation = engine.evaluate(facts: [.confirmed(.caffeine, isPresent: true)])
        #expect(ClarificationPlanner.questions(response: nil, evaluation: evaluation).isEmpty)
    }

    @Test("Never more than two questions, however many are proposed")
    func capsAtTwo() throws {
        // Four shaky guesses, each of which would fire a different rule.
        let facts: [FoodFact] = [.caffeine, .tomato, .spicy, .largePortion].map {
            FoodFact(category: $0, source: .visualInference, confidence: 0.4)
        }
        let evaluation = engine.evaluate(facts: facts)
        #expect(evaluation.unconfirmedMaterialFacts.count == 4)

        let proposed = [
            ClarificationQuestion(id: "a", question: "Was this caffeinated?", category: .caffeine),
            ClarificationQuestion(id: "b", question: "Did this have tomato in it?", category: .tomato),
            ClarificationQuestion(id: "c", question: "Was this spicy?", category: .spicy)
        ]
        let questions = ClarificationPlanner.questions(
            response: RecognitionResponse(
                proposedName: "Curry",
                proposedNameConfidence: 0.6,
                overallConfidence: 0.6,
                clarifications: proposed
            ),
            evaluation: evaluation
        )

        #expect(questions.count == ClarificationPlanner.maxQuestions)
        #expect(questions.count == 2)
    }

    @Test("The recogniser's own phrasing is preferred when it is relevant")
    func prefersProposedPhrasing() throws {
        let evaluation = engine.evaluate(facts: [
            FoodFact(category: .caffeine, source: .visualInference, confidence: 0.55)
        ])
        let response = try RecognitionResponseDecoder().decode(RecognitionFixture.caffeinatedTea.payload)

        let questions = ClarificationPlanner.questions(response: response, evaluation: evaluation)

        #expect(questions.count == 1)
        #expect(questions[0].question == "Was the tea caffeinated?")
    }

    @Test("Questions about things that were never seen are ignored")
    func ignoresIrrelevantProposedQuestions() {
        let evaluation = engine.evaluate(facts: [
            FoodFact(category: .spicy, source: .visualInference, confidence: 0.4)
        ])
        let response = RecognitionResponse(
            proposedName: "Soup",
            proposedNameConfidence: 0.7,
            overallConfidence: 0.7,
            clarifications: [
                ClarificationQuestion(id: "x", question: "Did this have alcohol in it?", category: .alcohol)
            ]
        )

        let questions = ClarificationPlanner.questions(response: response, evaluation: evaluation)

        #expect(questions.map(\.category) == [.spicy])
        #expect(questions[0].question == "Was this spicy?")
    }

    @Test("Answering a question produces a confirmed fact that wins")
    func answeringProducesUserCorrection() {
        let question = ClarificationQuestion(id: "q", question: "Was this caffeinated?", category: .caffeine)

        let yes = question.answer(true)
        #expect(yes.source == .userCorrection)
        #expect(yes.isPresent)
        #expect(yes.confidence == 1)

        let no = question.answer(false)
        #expect(no.isPresent == false)

        let guess = FoodFact(category: .caffeine, source: .visualInference, confidence: 0.55)
        #expect(engine.evaluate(facts: [guess, yes]).warnings.map(\.ruleID) == ["rule.caffeine.v1"])
        #expect(engine.evaluate(facts: [guess, no]).warnings.isEmpty)
    }

    @Test("The tea fixture asks one question, then produces one note when answered yes")
    func teaEndToEnd() throws {
        let response = try RecognitionResponseDecoder().decode(RecognitionFixture.caffeinatedTea.payload)

        let first = engine.evaluate(facts: response.candidateFacts)
        #expect(first.hasWarning == false)

        let questions = ClarificationPlanner.questions(response: response, evaluation: first)
        #expect(questions.count == 1)

        let answered = engine.evaluate(facts: response.candidateFacts + [questions[0].answer(true)])
        #expect(answered.displayWarnings.map(\.ruleID) == ["rule.caffeine.v1"])
        #expect(answered.displayWarnings[0].reason.contains("Caffeine"))
    }
}
