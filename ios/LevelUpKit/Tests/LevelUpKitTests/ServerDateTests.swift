import Foundation
import Testing
@testable import LevelUpKit

struct ServerDateTests {
    private let expected = Date(timeIntervalSince1970: 1_791_568_800.123) // 2026-10-09T18:00:00.123Z

    @Test(arguments: [
        "2026-10-09T18:00:00.123456Z",
        "2026-10-09T18:00:00.123Z",
        "2026-10-09T18:00:00.123456+00:00",
    ])
    func parsesFractionalSeconds(_ raw: String) throws {
        let date = try #require(ServerDate.parse(raw))
        #expect(abs(date.timeIntervalSince(expected)) < 0.001)
    }

    @Test func parsesWholeSeconds() throws {
        let date = try #require(ServerDate.parse("2026-10-09T18:00:00Z"))
        #expect(date.timeIntervalSince1970 == 1_791_568_800)
    }

    @Test func rejectsGarbage() {
        #expect(ServerDate.parse("yesterday") == nil)
    }
}
