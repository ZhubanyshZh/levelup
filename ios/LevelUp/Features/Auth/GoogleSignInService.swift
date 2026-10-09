@preconcurrency import GoogleSignIn
import LevelUpKit
import UIKit

@MainActor
enum GoogleSignInService {
    enum Failure: Error {
        case noPresenter
        case missingIDToken
    }

    static var isConfigured: Bool { AppConfig.fromBundle().googleClientID != nil }

    /// ID token Google или nil, если пользователь закрыл окно входа.
    static func signIn() async throws -> String? {
        guard let presenter = topViewController() else { throw Failure.noPresenter }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let token = result.user.idToken?.tokenString else { throw Failure.missingIDToken }
            return token
        } catch let error as GIDSignInError where error.code == .canceled {
            return nil
        }
    }

    static func signOut() {
        guard isConfigured else { return }
        GIDSignIn.sharedInstance.signOut()
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
