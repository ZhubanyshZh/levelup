import Foundation

/// Кодирование в формате API (snake_case, ISO 8601). Им же пользуется локальный кэш приложения.
public enum JSONCoding {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ServerDate.parse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unsupported date: \(string)"
                )
            }
            return date
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

/// Даты сервера: ISO 8601, иногда с микросекундами (6 знаков) — их стандартный парсер не берёт.
public enum ServerDate {
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle()

    public static func parse(_ raw: String) -> Date? {
        var string = raw
        if string.hasSuffix("+00:00") {
            string = String(string.dropLast(6)) + "Z"
        }
        if let dot = string.firstIndex(of: "."),
           let zone = string[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let digits = string[string.index(after: dot)..<zone]
            let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            string = String(string[..<dot]) + "." + millis + String(string[zone...])
            return try? withFraction.parse(string)
        }
        return try? withoutFraction.parse(string)
    }
}
