import LevelUpKit
import SwiftUI

struct CoachQuestionView: View {
    var initialText: String? = nil
    var captureID: UUID? = nil
    var questionIndex: Int? = nil
    @Environment(AppStore.self) private var store
    @AppStorage("speechLocale") private var speechLocale = SpeechLocale.default
    @State private var text = ""
    @State private var requestID = UUID()
    @State private var didFill = false
    @State private var answer: CoachAnswer?
    @State private var isAsking = false
    @State private var errorMessage: String?
    @State private var speech = SpeechRecognizer()
    @State private var beforeVoice = ""
    @State private var usedVoice = false
    @FocusState private var isTextFocused: Bool

    var body: some View {
        List {
            Section {
                TextField("Например: сколько я потратил на кафе в этом месяце?", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($isTextFocused)
                    .disabled(isAsking)
                HStack {
                    Button {
                        if speech.isRecording { speech.stop() }
                        else {
                            beforeVoice = text
                            usedVoice = true
                            Task { await speech.start(localeIdentifier: speechLocale) }
                        }
                    } label: {
                        Label(speech.isRecording ? "Остановить запись" : "Спросить голосом", systemImage: speech.isRecording ? "stop.fill" : "mic")
                            .frame(minHeight: 44)
                    }
                    .disabled(isAsking)
                    Spacer()
                    Button { Task { await ask() } } label: {
                        if isAsking { ProgressView() } else { Text("Спросить") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAsking || speech.isRecording || trimmed.isEmpty || trimmed.count > 4000 || (captureID != nil && answer != nil))
                }
                if let message = errorMessage ?? speech.errorMessage {
                    Text(message).foregroundStyle(.orange)
                }
            } header: { Text("Вопрос к данным") } footer: {
                Text("Расходы и доходы, тренировки, дни дневника, задачи с начисленным XP и общий XP. Ответ учитывает записи в приложении; суммы считает сервер.")
            }
            if let answer { CoachAnswerSections(answer: answer) }
        }
        .keyboardDismissal(isFocused: isTextFocused) { isTextFocused = false }
        .navigationTitle("Спросить коуча")
        .onAppear {
            guard !didFill else { return }
            text = initialText ?? store.coach.questionDraft.text
            requestID = store.coach.questionDraft.id
            didFill = true
        }
        .onDisappear { speech.cancel() }
        .onChange(of: text) { _, value in
            if captureID == nil && value != store.coach.questionDraft.text {
                requestID = UUID()
                store.coach.saveQuestionDraft(value, id: requestID)
            }
        }
        .onChange(of: speech.transcript) { _, value in
            if !value.isEmpty { text = [beforeVoice, value].filter { !$0.isEmpty }.joined(separator: " ") }
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func ask() async {
        isTextFocused = false
        isAsking = true
        errorMessage = nil
        defer { isAsking = false }
        do {
            answer = try await store.coach.ask(trimmed, captureID: captureID, questionIndex: questionIndex, requestID: requestID, source: usedVoice ? .voice : .text)
            if captureID == nil {
                store.coach.saveQuestionDraft("")
                requestID = UUID()
            }
        } catch { errorMessage = ErrorText.message(for: error) }
        await store.captures.loadInbox()
    }
}

struct CoachAnswerSections: View {
    let answer: CoachAnswer

    var body: some View {
        Section {
            if answer.metric == .unsupported || answer.value == nil {
                Text("Этот вопрос пока не поддерживается.").font(.headline)
            } else if let value = answer.value {
                Text(answer.currency.map { Money.text(value, currency: $0) } ?? value.formatted(.number.precision(.fractionLength(0...2))))
                    .font(.largeTitle.bold()).monospacedDigit()
                Text(metricLabel).foregroundStyle(.secondary)
            }
            Text(answer.explanation).textSelection(.enabled)
            LabeledContent("С", value: answer.startDate.date().formatted(date: .abbreviated, time: .omitted))
            LabeledContent("По", value: answer.endDate.date().formatted(date: .abbreviated, time: .omitted))
        } header: { Text("Ответ коуча") } footer: { Text("Только по записанным данным.") }
    }

    private var metricLabel: String {
        switch answer.metric {
        case .expense: String(localized: "Расходы")
        case .income: String(localized: "Доходы")
        case .workouts: String(localized: "Тренировок")
        case .journalDays: String(localized: "Дней с записью в дневнике")
        case .tasksDone: String(localized: "Задач с начисленным XP")
        case .xp: "XP"
        case .unsupported: ""
        }
    }
}
