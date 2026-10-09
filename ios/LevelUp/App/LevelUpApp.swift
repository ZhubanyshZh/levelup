import GoogleSignIn
import LevelUpKit
import SwiftUI
import UserNotifications

@main
struct LevelUpApp: App {
    @State private var session = SessionStore(config: .fromBundle())
    private let notificationPresenter = NotificationPresenter()

    init() {
        UNUserNotificationCenter.current().delegate = notificationPresenter
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
                .task { await session.restore() }
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .unavailable:
                ContentUnavailableView {
                    Label("Не удалось загрузить профиль", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(session.errorMessage ?? "")
                } actions: {
                    Button("Повторить") { Task { await session.restore() } }
                        .buttonStyle(.borderedProminent)
                }
            case .signedOut:
                SignInView()
            case .signedIn:
                if let store = session.appStore {
                    MainTabView()
                        .environment(store)
                }
            }
        }
        .animation(.default, value: session.state)
    }
}
