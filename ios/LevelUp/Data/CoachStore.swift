import Foundation
import LevelUpKit
import Observation

struct CoachQuestionDraft: Codable {
    var text: String
    var id: UUID
}

@MainActor
@Observable
final class CoachStore {
    private(set) var reports: [CoachReport]
    private(set) var answers: [CoachAnswer]
    private(set) var generating: Set<CoachKind> = []
    private(set) var applying: Set<UUID> = []
    private(set) var questionDraft: CoachQuestionDraft
    private let draftCache = LocalCache<CoachQuestionDraft>(name: "coach-question-draft")
    var errorMessage: String?
    private var epoch = UUID()
    private let api: APIClient
    private let reportCache = LocalCache<[CoachReport]>(name: "coach-reports")
    private let answerCache = LocalCache<[CoachAnswer]>(name: "coach-answers")
    var onUnauthorized: () -> Void = {}

    init(api: APIClient) {
        self.api = api
        questionDraft = draftCache.load() ?? CoachQuestionDraft(text: "", id: UUID())
        reports = reportCache.load() ?? []
        answers = answerCache.load() ?? []
    }

    func report(_ kind: CoachKind, goalID: UUID? = nil) -> CoachReport? {
        reports.first { $0.kind == kind && $0.goalId == goalID && $0.periodStart == kind.period() }
    }

    func load() async {
        let epoch = epoch
        do {
            async let newReports = api.coachReports()
            async let newAnswers = api.coachAnswers()
            let loaded = try await (newReports, newAnswers)
            guard epoch == self.epoch else { return }
            (reports, answers) = loaded
            reportCache.save(reports)
            answerCache.save(answers)
        } catch { handle(error) }
    }

    @discardableResult
    func generate(_ kind: CoachKind, goalID: UUID? = nil) async -> CoachReport? {
        guard !generating.contains(kind) else { return nil }
        generating.insert(kind)
        let epoch = epoch
        defer { generating.remove(kind) }
        errorMessage = nil
        do {
            let report = try await api.generateCoachReport(kind, goalID: goalID)
            guard epoch == self.epoch else { return nil }
            replace(report)
            return report
        } catch { handle(error); return nil }
    }

    func apply(_ action: CoachAction, in report: CoachReport, unscheduled: Bool = false) async -> CoachAppliedAction? {
        guard !applying.contains(action.id) else { return nil }
        applying.insert(action.id)
        let epoch = epoch
        defer { applying.remove(action.id) }
        errorMessage = nil
        do {
            let result = try await api.applyCoachAction(reportID: report.id, actionID: action.id, unscheduled: unscheduled)
            guard epoch == self.epoch else { return nil }
            replace(result.report)
            return result
        } catch { handle(error); return nil }
    }

    func ask(_ text: String, captureID: UUID? = nil, questionIndex: Int? = nil, requestID: UUID? = nil, source: CaptureSource = .text) async throws -> CoachAnswer {
        let epoch = epoch
        let answer = try await api.askCoach(text, captureID: captureID, questionIndex: questionIndex, requestID: requestID, source: source)
        guard epoch == self.epoch else { throw CancellationError() }
        answers.removeAll { $0.id == answer.id }
        answers.insert(answer, at: 0)
        answers = Array(answers.prefix(30))
        answerCache.save(answers)
        return answer
    }

    func saveQuestionDraft(_ text: String, id: UUID = UUID()) {
        questionDraft = CoachQuestionDraft(text: text, id: id)
        draftCache.save(questionDraft)
    }

    func reset() {
        epoch = UUID()
        reports = []
        answers = []
        generating = []
        applying = []
        questionDraft = CoachQuestionDraft(text: "", id: UUID())
        errorMessage = nil
    }

    private func replace(_ report: CoachReport) {
        reports.removeAll { $0.id == report.id }
        reports.insert(report, at: 0)
        reports = Array(reports.prefix(30))
        reportCache.save(reports)
    }

    private func handle(_ error: Error) {
        if (error as? APIError)?.isUnauthorized == true { onUnauthorized() }
        else { errorMessage = ErrorText.message(for: error) }
    }
}
