import Foundation
import Testing
@testable import KajutaBot

struct ISO8601ParsingTests {
    @Test("Daty backendu zachowują UTC, offset i precyzję ułamków sekund")
    func parsesBackendDates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let expected = try #require(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 10, day: 7, hour: 10
        )))
        #expect(parseISO8601("2026-10-07T10:00:00Z") == expected)
        #expect(parseISO8601("2026-10-07T12:00:00+02:00") == expected)
        let fractional = try #require(parseISO8601("2026-10-07T10:00:00.1234567Z"))
        #expect(abs(fractional.timeIntervalSince(expected) - 0.1234567) < 0.00001)
        #expect(parseISO8601(nil) == nil)
        #expect(parseISO8601("") == nil)
        #expect(parseISO8601("not-a-date") == nil)
    }

    @Test("UI i aktor sesji mogą równocześnie parsować różne formaty dat")
    func parsesConcurrently() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let expected = try #require(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 10, day: 7, hour: 10
        )))
        let inputs = ["2026-10-07T10:00:00Z", "2026-10-07T10:00:00.000Z", "2026-10-07T12:00:00+02:00"]
        let valid = await withTaskGroup(of: Bool.self) { group in
            for index in 0..<128 {
                let input = inputs[index % inputs.count]
                group.addTask { parseISO8601(input) == expected }
            }
            var allValid = true
            for await result in group { allValid = allValid && result }
            return allValid
        }
        #expect(valid)
    }
}
