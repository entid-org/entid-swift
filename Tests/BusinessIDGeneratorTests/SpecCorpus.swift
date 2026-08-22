package import BusinessIDWire
import Foundation

/// Reads the normative artefacts shipped under `spec/`.
///
/// They are not package resources. The rules bundle is an input of the
/// generator, read at build time, and embedding it would make every consumer
/// carry a payload the generated code makes useless. The conformance corpus is
/// a test input, and duplicating three hundred kilobytes of it into a resource
/// bundle would only create a second copy to keep in step.
enum SpecCorpus {
    /// The repository root, derived from this file rather than from the working
    /// directory, so the tests run the same from any launcher.
    static let root: URL = {
        if let override = ProcessInfo.processInfo.environment["BUSINESSID_SPEC_ROOT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // BusinessIDGeneratorTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository root
    }()

    static func specFile(_ name: String) throws -> [UInt8] {
        try [UInt8](Data(contentsOf: root.appending(path: "spec").appending(path: name)))
    }

    static func rulesBundle() throws -> [UInt8] {
        try specFile("businessid-rules.binpb")
    }

    static func conformance() throws -> Libbusinessid_Conformance_V1_ConformanceBundle {
        try Libbusinessid_Conformance_V1_ConformanceBundle(
            serializedBytes: Data(specFile("businessid-conformance.binpb"))
        )
    }

    /// The `load_ruleset` cases, which address the generator rather than the
    /// engine: a truncated bundle or one carrying a call cycle must make
    /// generation fail.
    static func loaderCases() throws -> [Libbusinessid_Conformance_V1_ConformanceCase] {
        try conformance().cases.filter { $0.operation == .loadRuleset }
    }
}

/// What `rules.lock` names, read rather than repeated.
///
/// A rules update touches one file. A test that repeated the version would go
/// stale in one place and not another, and the mismatch would look like a
/// defect of the engine.
enum RulesLockFixture {
    static let rulesVersion: String = field("rules_version") ?? ""

    static func field(_ name: String) -> String? {
        guard
            let text = try? String(
                contentsOf: SpecCorpus.root.appending(path: "rules.lock"), encoding: .utf8
            )
        else { return nil }
        return
            text
            .split(separator: "\n")
            .first { $0.hasPrefix("\(name) = ") }
            .map { String($0.split(separator: "\"")[1]) }
    }
}
