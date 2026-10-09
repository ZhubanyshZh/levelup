@preconcurrency import AVFoundation
import Foundation
import Observation
@preconcurrency import Speech

/// Голос → текст через Apple Speech. Бесплатно; текст появляется, пока говоришь.
@MainActor
@Observable
final class SpeechRecognizer {
    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var errorMessage: String?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(localeIdentifier: String) async {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""

        guard await Self.requestSpeechAuthorization() else {
            errorMessage = String(localized: "Разреши распознавание речи: Настройки → Level Up.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = String(localized: "Разреши доступ к микрофону: Настройки → Level Up.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable
        else {
            errorMessage = String(localized: "Распознавание речи сейчас недоступно. Попробуй написать текстом.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            let engine = AVAudioEngine()
            Self.installTap(on: engine.inputNode, request: request)
            engine.prepare()
            try engine.start()

            self.engine = engine
            self.request = request
            task = Self.makeTask(recognizer: recognizer, request: request) { [weak self] text, isFinal in
                Task { @MainActor in self?.receive(text: text, isFinal: isFinal) }
            }
            isRecording = true
        } catch {
            errorMessage = String(localized: "Не удалось включить микрофон.")
            stop()
        }
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        engine = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        task?.cancel()
        task = nil
        stop()
    }

    private func receive(text: String?, isFinal: Bool) {
        if let text {
            transcript = text
        }
        if isFinal {
            task = nil
            if isRecording {
                stop()
            }
        }
    }

    // Колбэки аудио и Speech приходят не с главного потока, поэтому замыкания
    // создаются вне MainActor — иначе Swift 6 остановит приложение на проверке изоляции.

    nonisolated private static func installTap(
        on node: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest
    ) {
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func makeTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }

    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
