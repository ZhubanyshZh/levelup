import LevelUpKit
import SwiftUI

/// Проверка связи с сервером и общего хранилища для виджетов.
struct DiagnosticsView: View {
    @Environment(SessionStore.self) private var session
    @State private var health: HealthState = .checking

    var body: some View {
        List {
            StatusRow(title: "Сервер", detail: serverDetail, status: health.status)
            StatusRow(
                title: "Виджеты (App Group)",
                detail: session.config.appGroupID,
                status: SnapshotStore(appGroupID: session.config.appGroupID).isAvailable ? .ok : .failed
            )
        }
        .navigationTitle("Проверка связи")
        .refreshable { await checkHealth() }
        .task { await checkHealth() }
    }

    private var serverDetail: String {
        switch health {
        case .ok(let version): String(localized: "Версия \(version)")
        case .checking, .failed: session.config.apiBaseURL.absoluteString
        }
    }

    private func checkHealth() async {
        do {
            let status = try await session.api.health()
            health = status.status == "ok" ? .ok(version: status.version) : .failed
        } catch {
            health = .failed
        }
    }
}

private enum HealthState {
    case checking
    case ok(version: String)
    case failed

    var status: StatusRow.Status {
        switch self {
        case .checking: .checking
        case .ok: .ok
        case .failed: .failed
        }
    }
}

private struct StatusRow: View {
    enum Status { case checking, ok, failed }

    let title: LocalizedStringKey
    let detail: String
    let status: Status

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch status {
            case .checking:
                ProgressView()
            case .ok:
                Label("Работает", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Label("Недоступно", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        }
        .labelStyle(.iconOnly)
    }
}
