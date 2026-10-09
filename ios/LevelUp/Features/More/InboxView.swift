import LevelUpKit
import SwiftUI

/// «Входящие»: всё, что ещё не разложено. Отсюда ничего не пропадает само.
struct InboxView: View {
    @Environment(AppStore.self) private var store
    @State private var opened: Capture?
    @State private var questionCapture: Capture?

    var body: some View {
        let captures = store.captures
        List {
            if !captures.outbox.isEmpty {
                Section {
                    ForEach(captures.outbox) { queued in
                        Text(queued.request.text)
                            .lineLimit(3)
                            .swipeActions {
                                Button("Удалить", systemImage: "trash", role: .destructive) {
                                    captures.discard(queued)
                                }
                            }
                    }
                    Button {
                        Task { await captures.flushOutbox() }
                    } label: {
                        Label("Отправить сейчас", systemImage: "arrow.up.circle")
                    }
                    .disabled(captures.isFlushing)
                } header: {
                    Text("Ждут интернета")
                }
            }

            if !captures.inbox.isEmpty {
                Section {
                    ForEach(captures.inbox) { capture in
                        Button {
                            if capture.items.contains(where: { $0.kind == .question && $0.include }) {
                                questionCapture = capture
                            } else { opened = capture }
                        } label: {
                            InboxRow(capture: capture)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Убрать", systemImage: "trash", role: .destructive) {
                                Task { await captures.dismiss(capture) }
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if captures.pendingCount == 0 {
                ContentUnavailableView(
                    "Всё разложено",
                    systemImage: "tray",
                    description: Text("Сюда попадают записи, которые ИИ не смог разобрать или которые ждут подтверждения.")
                )
            }
        }
        .navigationTitle("Входящие")
        .refreshable { await captures.loadInbox() }
        .task { await captures.loadInbox() }
        .sheet(item: $opened) { CaptureSheet(initialCapture: $0) }
        .sheet(item: $questionCapture) { capture in
            let index = capture.items.firstIndex { $0.kind == .question && $0.include }
            let item = index.map { capture.items[$0] }
            NavigationStack {
                CoachQuestionView(initialText: capture.status == .failed ? capture.text : item.map { [$0.title, $0.details].compactMap { $0 }.joined(separator: " ") }, captureID: capture.id, questionIndex: index)
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("Готово") { questionCapture = nil }
                    } }
            }
        }
    }
}

private struct InboxRow: View {
    let capture: Capture

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(capture.text)
                .lineLimit(3)
            Label(statusText, systemImage: statusSymbol)
                .font(.caption)
                .foregroundStyle(capture.status == .failed ? .orange : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private var statusText: String {
        switch capture.status {
        case .failed: ErrorText.capture(capture.errorCode)
        case .parsed: String(localized: "Ждёт подтверждения")
        case .deferred: String(localized: "Ждёт появления раздела")
        case .confirmed, .undone: ""
        }
    }

    private var statusSymbol: String {
        switch capture.status {
        case .failed: "exclamationmark.circle"
        case .parsed: "hand.tap"
        default: "clock"
        }
    }
}
