// The testee is driven as a subprocess, which no simulator can do, so this
// whole target is compiled out anywhere but macOS rather than skipped at run
// time. A skipped test reads as a passing one in a summary; an absent one does
// not.
#if os(macOS)

package import BusinessIDWire
import Foundation

/// Reading the corpus, and driving the built testee.
///
/// These tests read the corpus. The testee must not, and proving that is what
/// they are for — so the reader lives here, in the test target, and nothing in
/// `Sources/BusinessIDTestee` or `Sources/businessid-testee` can reach it.
enum TesteeHarness {
    static let root: URL = {
        if let override = ProcessInfo.processInfo.environment["BUSINESSID_SPEC_ROOT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    static func corpus() throws -> Libbusinessid_Conformance_V1_ConformanceBundle {
        let path = root.appending(path: "spec/businessid-conformance.binpb")
        return try Libbusinessid_Conformance_V1_ConformanceBundle(
            serializedBytes: [UInt8](try Data(contentsOf: path))
        )
    }

    /// A request built from a case, exactly as the runner builds one.
    static func request(
        for testCase: Libbusinessid_Conformance_V1_ConformanceCase
    ) -> Libbusinessid_Testee_V1_TesteeRequest {
        var request = Libbusinessid_Testee_V1_TesteeRequest()
        request.caseID = testCase.id
        request.operation = testCase.operation
        request.input = testCase.input
        request.kind = testCase.kind
        if testCase.hasCountryCode { request.countryCode = testCase.countryCode }
        // A case that states no profile leaves the field absent, which is what
        // lets a definition's default apply.
        if !testCase.profile.isEmpty { request.profile = testCase.profile }
        if testCase.hasRulesPayload { request.rulesPayload = testCase.rulesPayload }
        return request
    }

    // MARK: - The built executable

    struct TesteeUnavailable: Error, CustomStringConvertible {
        var description: String {
            "businessid-testee was not found in .build; build it or set BUSINESSID_TESTEE"
        }
    }

    /// `Bundle.main` inside an XCTest bundle points at the test runner, not at
    /// the package products, so the search starts from this file instead.
    static func executable() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["BUSINESSID_TESTEE"] {
            return URL(fileURLWithPath: override)
        }
        let build = root.appending(path: ".build")
        let manager = FileManager.default
        var candidates: [URL] = []
        for triple in (try? manager.contentsOfDirectory(at: build, includingPropertiesForKeys: nil)) ?? [] {
            for configuration in ["debug", "release"] {
                let candidate = triple.appending(path: configuration).appending(path: "businessid-testee")
                if manager.isExecutableFile(atPath: candidate.path) { candidates.append(candidate) }
            }
        }
        guard let newest = candidates.max(by: { modified($0) < modified($1) }) else {
            throw TesteeUnavailable()
        }
        return newest
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    // MARK: - The wire protocol

    static func frame(_ payload: [UInt8]) -> Data {
        let length = UInt32(payload.count)
        return Data(
            [
                UInt8(truncatingIfNeeded: length),
                UInt8(truncatingIfNeeded: length >> 8),
                UInt8(truncatingIfNeeded: length >> 16),
                UInt8(truncatingIfNeeded: length >> 24),
            ] + payload
        )
    }

    static func unframe(_ data: Data) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        var offset = data.startIndex
        while data.distance(from: offset, to: data.endIndex) >= 4 {
            let header = [UInt8](data[offset..<data.index(offset, offsetBy: 4)])
            let length =
                Int(header[0]) | Int(header[1]) << 8 | Int(header[2]) << 16 | Int(header[3]) << 24
            let start = data.index(offset, offsetBy: 4)
            guard data.distance(from: start, to: data.endIndex) >= length else { break }
            messages.append([UInt8](data[start..<data.index(start, offsetBy: length)]))
            offset = data.index(start, offsetBy: length)
        }
        return messages
    }

    /// Sends every request through one subprocess, optionally from a working
    /// directory of the caller's choosing.
    static func exchange(
        _ requests: [Libbusinessid_Testee_V1_TesteeRequest],
        workingDirectory: URL? = nil
    ) throws -> [Libbusinessid_Testee_V1_TesteeResponse] {
        let process = Process()
        process.executableURL = try executable()
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()

        var payload = Data()
        for request in requests { payload += frame(try request.serializedBytes()) }
        try input.fileHandleForWriting.write(contentsOf: payload)
        try input.fileHandleForWriting.close()

        let raw = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return try unframe(raw).map {
            try Libbusinessid_Testee_V1_TesteeResponse(serializedBytes: $0)
        }
    }
}
#endif
