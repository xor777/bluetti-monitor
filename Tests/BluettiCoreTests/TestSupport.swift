import Foundation

typealias TestCase = (name: String, body: () throws -> Void)

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") throws {
    guard actual == expected else {
        throw TestFailure(description: "Expected \(expected), got \(actual). \(message)")
    }
}

func expectNil<T>(_ actual: T?, _ message: String = "") throws {
    guard actual == nil else {
        throw TestFailure(description: "Expected nil, got \(String(describing: actual)). \(message)")
    }
}

func expectThrows<T, E: Error & Equatable>(
    _ expected: E,
    _ body: () throws -> T
) throws {
    do {
        _ = try body()
        throw TestFailure(description: "Expected \(expected), but no error was thrown")
    } catch let error as E {
        try expectEqual(error, expected)
    } catch {
        throw TestFailure(description: "Expected \(expected), got \(error)")
    }
}
