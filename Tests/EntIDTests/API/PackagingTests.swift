import Foundation
import Testing

@testable import EntID

/// The properties that make this a generated engine rather than an interpreter.
///
/// Each one is easy to reintroduce by accident — an import added while
/// debugging, a resource added for a test fixture, a registry type added "for
/// later" — and none of them would fail any other test. They are asserted
/// against the repository itself so that the failure lands on whoever
/// reintroduces one.
@Suite("Packaging")
struct PackagingTests {
    static let root: URL = {
        if let override = ProcessInfo.processInfo.environment["ENTID_SPEC_ROOT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // API
            .deletingLastPathComponent()  // EntIDTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository root
    }()

    static func librarySources() throws -> [(name: String, text: String)] {
        let library = root.appending(path: "Sources/EntID")
        let manager = FileManager.default
        guard let walker = manager.enumerator(at: library, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            files.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return files
    }

    @Test("The shipped library carries no bundle and no Protobuf")
    func noInterpreterInTheLibrary() throws {
        // Decoding a bundle, resolving an opcode and walking the IR are the
        // generator's work. Shipping any of it would put the whole validator
        // and a sixty three opcode execution machine in every caller's process.
        let forbidden = [
            "SwiftProtobuf", "Entid_", "RuleBundle", "OpKind", "binpb", "serializedBytes",
        ]
        for file in try Self.librarySources() {
            for token in forbidden {
                #expect(!file.text.contains(token), Comment(rawValue: "\(file.name) mentions \(token)"))
            }
        }
    }

    @Test("No .binpb is a resource of the package")
    func noBundleResource() throws {
        // The rules bundle is an input of the generator, read at build time.
        // Embedding it would make every caller carry a payload the generated
        // code makes useless, and would imply a decoder to read it.
        let manager = FileManager.default
        let sources = Self.root.appending(path: "Sources")
        let walker = try #require(manager.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in walker {
            #expect(url.pathExtension != "binpb", Comment(rawValue: url.lastPathComponent))
        }

        let manifest = try String(
            contentsOf: Self.root.appending(path: "Package.swift"), encoding: .utf8
        )
        #expect(!manifest.contains("resources:"))
        #expect(!manifest.contains(".copy("))
        #expect(!manifest.contains(".process("))
    }

    @Test("The library target declares no dependency")
    func libraryHasNoDependency() throws {
        let manifest = try String(
            contentsOf: Self.root.appending(path: "Package.swift"), encoding: .utf8
        )
        let declaration = try #require(manifest.range(of: #"name: "EntID","#))
        // Everything up to the closing of that target declaration.
        let body = manifest[declaration.upperBound...].prefix(while: { $0 != ")" })
        #expect(!body.contains("dependencies:"), Comment(rawValue: String(body)))
    }

    @Test("No registry type is exposed, not even an experimental one")
    func noRegistryType() throws {
        // A public type is a commitment SemVer freezes. The registry interface
        // will be specified when it is built; reserving a name for it now would
        // reserve the wrong one.
        for file in try Self.librarySources() {
            for token in ["RegistryProvider", "registryLookup", "RegistryResult"] {
                #expect(!file.text.contains(token), Comment(rawValue: "\(file.name) mentions \(token)"))
            }
        }
        // The reason code stays reserved in the registry, and unreachable.
        #expect(ReasonCode.allCases.contains(.registryNotConfigured))
    }

    @Test("No validation method is asynchronous")
    func validationIsSynchronous() throws {
        // Local validation stays synchronous permanently. Making one of these
        // async "in case" would transform every caller for a lookup that will
        // live in another module.
        for file in try Self.librarySources() {
            #expect(!file.text.contains("public func canonicalize") || !file.text.contains("async"))
            let asyncPublic = file.text.range(
                of: #"public func [A-Za-z]+\([^)]*\)[^{]*async"#, options: .regularExpression
            )
            #expect(asyncPublic == nil, Comment(rawValue: file.name))
        }
    }

    @Test("The library imports no UI framework and no networking")
    func noPlatformCoupling() throws {
        for file in try Self.librarySources() {
            for framework in ["UIKit", "AppKit", "SwiftUI", "URLSession", "Network", "CryptoKit"] {
                #expect(
                    !file.text.contains("import \(framework)"),
                    Comment(rawValue: "\(file.name) imports \(framework)")
                )
            }
        }
    }

    @Test("The generated code is present and states the locked rules version")
    func generatedCodeIsPresent() throws {
        let generated = Self.root.appending(path: "Sources/EntID/Generated")
        for name in ["GeneratedRuleset.swift", "GeneratedPrograms.swift", "GeneratedLiterals.swift"] {
            let text = try String(contentsOf: generated.appending(path: name), encoding: .utf8)
            #expect(text.hasPrefix("// Generated by entid-gen. Do not edit by hand."))
            #expect(text.contains("swift-format-ignore-file"))
        }

        let lock = try String(
            contentsOf: Self.root.appending(path: "rules.lock"), encoding: .utf8
        )
        let locked = try #require(
            lock.split(separator: "\n")
                .first { $0.hasPrefix("rules_version = ") }
                .map { String($0.split(separator: "\"")[1]) }
        )
        #expect(EntIDEngine.default.rulesVersion == locked)
    }

    @Test("Every reachable reason code is produced by some input")
    func reachableReasonCodesAreReached() {
        // A reason code the engine can emit but nothing exercises is a branch
        // nobody has read. The four unreachable ones are named, not skipped.
        let unreachable: Set<ReasonCode> = [
            // Reserved for the deferred registry level.
            .registryNotConfigured,
            // Refusals of a ruleset, which a generated engine never loads.
            .incompatibleRuleset, .invalidRuleset,
            // A Swift String is always well formed Unicode.
            .invalidEncoding,
            // No format program in the published rules reports it; the code
            // stays in the registry for a ruleset that would.
            .unsupportedFormat,
        ]

        let engine = EntIDEngine.default
        let probes: [IdentifierInput] = [
            IdentifierInput(kind: "siren", value: "012345674"),
            IdentifierInput(kind: "siren", value: ""),
            IdentifierInput(kind: "siren", value: "01234567"),
            IdentifierInput(kind: "siren", value: "01234567A"),
            IdentifierInput(kind: "siren", value: "012345670"),
            IdentifierInput(kind: "euid", value: "FRXXX.012345674"),
            IdentifierInput(kind: "cegjegyzekszam", value: "0123456789"),
            IdentifierInput(kind: "vat", value: "BE0123456749", countryCode: "FR"),
            IdentifierInput(kind: "vat", value: "0123456749"),
            IdentifierInput(kind: "siren", value: "012345674", countryCode: "DE"),
            IdentifierInput(kind: "no_such_kind", value: "X"),
            IdentifierInput(kind: "siren", value: String(repeating: "1", count: 2000)),
            // `company-number-prefix-406`: a prefix no documented variant uses.
            IdentifierInput(kind: "company_number", value: "ZZ123456"),
            // `vat-at-001`: a format that validates whose checksum this
            // ruleset cannot conclude on.
            IdentifierInput(kind: "vat", value: "ATU01234567"),
        ]

        var seen: Set<ReasonCode> = []
        for probe in probes {
            for report in [engine.validate(probe), engine.validateFormat(probe)] {
                seen.insert(report.format.reasonCode)
                seen.insert(report.checksum.reasonCode)
            }
            seen.insert(engine.canonicalize(probe).reasonCode)
        }

        let expected = Set(ReasonCode.allCases).subtracting(unreachable)
        let missed = expected.subtracting(seen)
        #expect(missed.isEmpty, Comment(rawValue: missed.map(\.rawValue).sorted().joined(separator: ", ")))
    }
}
