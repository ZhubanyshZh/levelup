import LevelUpKit
import SwiftUI

/// Единый ввод: голос или текст → ИИ → карточки для проверки → сохранение.
struct CaptureSheet: View {
    /// Открыть запись из «Входящих» сразу на нужном шаге.
    var initialCapture: Capture?
    /// .voice — сразу слушать (Siri, виджет, Пункт управления); .text — клавиатура.
    var startMode: AppRoute.CaptureMode = .text

    private enum Phase: Equatable {
        case input
        case working
        case preview(Capture)
        case failed(Capture)
        case deferred(Capture)
        case queued
        case saved(String)
    }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speechLocale") private var speechLocale = SpeechLocale.default
    @State private var speech = SpeechRecognizer()
    @State private var phase: Phase = .input
    @State private var text = ""
    @State private var textBeforeRecording = ""
    @State private var usedVoice = false
    @State private var items: [CaptureItem] = []
    @State private var errorMessage: String?
    @State private var savedCount = 0
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .keyboardDismissal(isFocused: isEditorFocused) { isEditorFocused = false }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { dismiss() }
                            .disabled(phase == .working)
                    }
                }
                .overlay(alignment: .bottom) { ErrorBanner(message: $errorMessage) }
        }
        .interactiveDismissDisabled(phase == .working)
        .sensoryFeedback(.success, trigger: savedCount)
        .onAppear {
            if let initialCapture {
                show(initialCapture)
            } else if startMode == .voice || startMode == .expense {
                toggleRecording()
            } else {
                isEditorFocused = true
            }
        }
        .onDisappear { speech.cancel() }
        .onChange(of: speech.transcript) { _, transcript in
            guard !transcript.isEmpty else { return }
            text = [textBeforeRecording, transcript].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    private var title: LocalizedStringKey {
        switch phase {
        case .input, .working: startMode == .expense ? "Новая трата" : "Новая запись"
        case .preview: "Проверь"
        case .failed, .deferred, .queued: "Входящие"
        case .saved: "Готово"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .input: inputView
        case .working: workingView
        case .preview(let capture): previewView(capture)
        case .failed(let capture): failedView(capture)
        case .deferred(let capture): deferredView(capture)
        case .queued: queuedView
        case .saved(let summary): savedView(summary)
        }
    }

    // MARK: Ввод

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var inputView: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($isEditorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                if text.isEmpty {
                    Text(startMode == .expense
                         ? LocalizedStringKey("Сколько и на что? Например: «такси 3500» или «кофе 1200 и обед 4000».")
                         : LocalizedStringKey("Скажи или напиши что угодно: дела, мысли, «запомни, что…». ИИ сам разложит по местам."))
                        .foregroundStyle(.tertiary)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            .background(.fill.tertiary, in: .rect(cornerRadius: 18))

            if let speechError = speech.errorMessage {
                Text(speechError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                Button(action: toggleRecording) {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(speech.isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.tint), in: .circle)
                        .symbolEffect(.pulse, isActive: speech.isRecording)
                }
                .accessibilityLabel(speech.isRecording ? Text("Остановить запись") : Text("Говорить"))

                Button {
                    Task { await submit() }
                } label: {
                    Label("Разобрать", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmedText.isEmpty || speech.isRecording)
            }

            Text(speech.isRecording ? "Слушаю… Нажми ■, когда закончишь." : "Нажми на микрофон и говори")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func toggleRecording() {
        if speech.isRecording {
            speech.stop()
        } else {
            isEditorFocused = false
            textBeforeRecording = trimmedText
            usedVoice = true
            Task { await speech.start(localeIdentifier: speechLocale) }
        }
    }

    private func submit() async {
        speech.stop()
        let value = trimmedText
        guard !value.isEmpty else { return }
        phase = .working
        do {
            switch try await store.captures.send(text: value, source: usedVoice ? .voice : .text) {
            case .queued: phase = .queued
            case .processed(let result): show(result.capture)
            }
        } catch {
            errorMessage = ErrorText.message(for: error)
            phase = .input
        }
    }

    private var workingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Разбираю…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Предпросмотр

    private func show(_ capture: Capture) {
        text = capture.text
        switch capture.status {
        case .parsed:
            items = capture.items
            phase = .preview(capture)
        case .failed:
            phase = .failed(capture)
        case .deferred:
            phase = .deferred(capture)
        case .confirmed, .undone:
            phase = .saved(String(localized: "Запись уже обработана."))
        }
    }

    private func previewView(_ capture: Capture) -> some View {
        List {
            if let reply = capture.reply {
                Section {
                    Label(reply, systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                }
            }
            if items.isEmpty {
                Section {
                    Text("ИИ не нашёл здесь ни задач, ни фактов. Нажми «Сохранить», чтобы убрать запись из «Входящих».")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach($items) { $item in
                Section {
                    CaptureItemCard(item: $item)
                }
            }
            Section("Исходный текст") {
                Text(capture.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await confirm(capture) }
            } label: {
                Text(saveTitle)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }

    private var saveTitle: String {
        let count = items.filter(\.include).count
        return count == 0 ? String(localized: "Сохранить") : String(localized: "Сохранить (\(count))")
    }

    private func confirm(_ capture: Capture) async {
        isEditorFocused = false
        phase = .working
        do {
            let result = try await store.captures.confirm(capture, items: items)
            store.apply(result)
            savedCount += 1
            phase = .saved(summary(of: result))
            try? await Task.sleep(for: .seconds(1.4))
            dismiss()
        } catch {
            errorMessage = ErrorText.message(for: error)
            phase = .preview(capture)
        }
    }

    private func summary(of result: CaptureResult) -> String {
        CaptureSummary.text(of: result)
    }

    // MARK: Остальные состояния

    private func failedView(_ capture: Capture) -> some View {
        ContentUnavailableView {
            Label("Сохранено во «Входящих»", systemImage: "tray.and.arrow.down")
        } description: {
            Text(ErrorText.capture(capture.errorCode))
        } actions: {
            if ErrorText.needsAISettings(capture.errorCode) {
                NavigationLink("Настроить ИИ") { AISettingsView() }
                    .buttonStyle(.borderedProminent)
            }
            Button("Разобрать снова") {
                Task { await retry(capture) }
            }
            .buttonStyle(.bordered)
        }
    }

    private func retry(_ capture: Capture) async {
        phase = .working
        do {
            show(try await store.captures.retry(capture).capture)
        } catch {
            errorMessage = ErrorText.message(for: error)
            phase = .failed(capture)
        }
    }

    private func deferredView(_ capture: Capture) -> some View {
        List {
            Section {
                Text("Вопросы можно задать коучу. Остальные записи ждут здесь, пока ты их разберёшь.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(capture.items.enumerated()), id: \.offset) { index, item in
                if item.include && !item.supported {
                    if item.kind == .question {
                        NavigationLink {
                            CoachQuestionView(initialText: [item.title, item.details].compactMap { $0 }.joined(separator: " "), captureID: capture.id, questionIndex: index)
                        } label: { Label(item.title, systemImage: "questionmark.bubble") }
                    } else {
                        Label(item.title, systemImage: item.kind?.symbol ?? "tray")
                    }
                }
            }
            Section {
                Button("Убрать из «Входящих»", role: .destructive) {
                    Task {
                        await store.captures.dismiss(capture)
                        dismiss()
                    }
                }
            }
        }
    }

    private var queuedView: some View {
        ContentUnavailableView {
            Label("Сохранено на телефоне", systemImage: "wifi.slash")
        } description: {
            Text("Нет связи с сервером. Запись отправится сама, когда появится интернет.")
        } actions: {
            Button("Готово") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func savedView(_ summary: String) -> some View {
        ContentUnavailableView {
            Label("Сохранено", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.tint)
        } description: {
            Text(summary)
        }
    }
}

enum SpeechLocale {
    static var `default`: String {
        Locale.current.language.languageCode?.identifier == "en" ? "en-US" : "ru-RU"
    }
}
