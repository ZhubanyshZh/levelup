import Foundation

/// Настройки сборки из Info.plist (значения приходят из ios/Config/*.xcconfig).
public struct AppConfig: Sendable {
    public let apiBaseURL: URL
    public let appGroupID: String
    public let googleClientID: String?

    public init(apiBaseURL: URL, appGroupID: String, googleClientID: String?) {
        self.apiBaseURL = apiBaseURL
        self.appGroupID = appGroupID
        self.googleClientID = googleClientID
    }

    public static func fromBundle(_ bundle: Bundle = .main) -> AppConfig {
        func value(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        let apiURL = value("LUAPIBaseURL").flatMap(URL.init(string:))
            ?? URL(string: "http://localhost:8000")!
        return AppConfig(
            apiBaseURL: apiURL,
            appGroupID: value("LUAppGroupID") ?? "",
            googleClientID: value("GIDClientID")
        )
    }
}
