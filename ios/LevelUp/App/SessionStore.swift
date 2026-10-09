import Foundation
import LevelUpKit
import Observation
import UIKit
import WidgetKit

/// Состояние входа. Разлогинивает только когда сервер отверг сессию — не при проблемах с сетью.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case loading
        /// Сессия есть, но профиль не загрузился и в кэше его нет.
        case unavailable
        case signedOut
        case signedIn(User)
    }

    private(set) var state: State = .loading
    private(set) var isWorking = false
    /// Данные вошедшего пользователя; nil, пока никто не вошёл.
    private(set) var appStore: AppStore?
    var errorMessage: String?

    let config: AppConfig
    let api: APIClient
    let snapshots: SnapshotStore
    private let deviceCredentials = DeviceCredentialStore()
    private let userCache = UserCache()

    init(config: AppConfig) {
        self.config = config
        api = APIClient(baseURL: config.apiBaseURL, tokenStore: KeychainTokenStore())
        snapshots = SnapshotStore(appGroupID: config.appGroupID)
    }

    func restore() async {
        guard api.hasSession else {
            signOutLocally()
            return
        }
        // Показываем профиль из кэша сразу, даже без сети, затем обновляем.
        if let cached = userCache.load() {
            enter(cached)
        }
        do {
            apply(try await api.me())
            await syncTimezone()
        } catch let error as APIError where error.isUnauthorized {
            signOutLocally()
        } catch {
            errorMessage = ErrorText.message(for: error)
            if userCache.load() == nil {
                state = .unavailable
            }
        }
    }

    func continueWithoutAccount() async {
        let secret = deviceCredentials.secret()
        let client = clientInfo
        await perform { self.apply(try await $0.signInWithDevice(secret: secret, client: client).user) }
    }

    func signInWithGoogle() async {
        errorMessage = nil
        do {
            guard let idToken = try await GoogleSignInService.signIn() else { return }
            let client = clientInfo
            await perform { self.apply(try await $0.signInWithGoogle(idToken: idToken, client: client).user) }
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
    }

    /// Гость подключает Google: аккаунт и все данные остаются те же.
    func linkGoogle() async {
        errorMessage = nil
        do {
            guard let idToken = try await GoogleSignInService.signIn() else { return }
            await perform { self.apply(try await $0.linkGoogle(idToken: idToken)) }
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
    }

    func signOut() async {
        await api.signOut()
        GoogleSignInService.signOut()
        signOutLocally()
    }

    private func perform(_ operation: (APIClient) async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await operation(api)
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
    }

    private func apply(_ user: User) {
        userCache.save(user)
        errorMessage = nil
        enter(user)
        updateWidget(appStore?.progress.progress ?? .initial)
    }

    private func enter(_ user: User) {
        if appStore == nil {
            appStore = AppStore(
                api: api,
                onUnauthorized: { [weak self] in self?.sessionExpired() },
                onProgress: { [weak self] in self?.updateWidget($0) }
            )
        }
        state = .signedIn(user)
    }

    /// Виджеты показывают уровень и опыт из общего хранилища App Group.
    private func updateWidget(_ progress: LevelProgress) {
        guard case .signedIn(let user) = state else { return }
        writeSnapshot(WidgetSnapshot(
            isSignedIn: true,
            displayName: user.displayName,
            level: progress.level,
            xp: progress.xpInLevel,
            xpForNextLevel: progress.xpForNextLevel,
            updatedAt: .now
        ))
    }

    /// Сервер отверг сессию (например, refresh-токен отозван).
    private func sessionExpired() {
        guard case .signedIn = state else { return }
        signOutLocally()
        errorMessage = String(localized: "Сессия завершилась. Войди снова.")
    }

    private func signOutLocally() {
        appStore?.reset()
        appStore = nil
        userCache.clear()
        state = .signedOut
        writeSnapshot(.signedOut)
    }

    /// Пользователь мог переехать или путешествовать: «завтра» должно считаться по месту.
    private func syncTimezone() async {
        guard case .signedIn(let user) = state, user.timezone != TimeZone.current.identifier else { return }
        if let updated = try? await api.updateMe(UserUpdate(timezone: TimeZone.current.identifier)) {
            apply(updated)
        }
    }

    private func writeSnapshot(_ snapshot: WidgetSnapshot) {
        try? snapshots.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var clientInfo: ClientInfo {
        ClientInfo(
            locale: Bundle.main.preferredLocalizations.first,
            timezone: TimeZone.current.identifier,
            deviceName: UIDevice.current.model
        )
    }
}

/// Последний загруженный профиль — чтобы приложение открывалось мгновенно и без сети.
private struct UserCache {
    private let key = "levelup.cachedUser"

    func load() -> User? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(User.self, from: $0) }
    }

    func save(_ user: User) {
        UserDefaults.standard.set(try? JSONEncoder().encode(user), forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
