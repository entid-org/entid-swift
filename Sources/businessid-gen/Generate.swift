import BusinessIDGenerator
import Foundation

/// Reads `businessid-rules.binpb`, applies the twenty five load checks and
/// emits the Swift the engine ships.
///
/// It runs when the engine is built, never when it validates. Refusing is a
/// property of generation time: an engine made from an accepted bundle meets no
/// construction it does not understand, because everything it contains came out
/// of one.
///
///     businessid-gen --rules spec/businessid-rules.binpb \
///                    --lock rules.lock \
///                    --out Sources/BusinessID/Generated \
///                    [--check]
///
/// `--check` emits nothing and reports whether the committed files are what
/// this bundle produces, which is what CI runs.
@main
struct Generate {
    static func main() {
        do {
            try run(CommandLine.arguments)
        } catch let error as GeneratorFailure {
            FileHandle.standardError.write(Data("businessid-gen: \(error.message)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("businessid-gen: \(error)\n".utf8))
            exit(1)
        }
    }

    struct GeneratorFailure: Error {
        let message: String
    }

    static func run(_ arguments: [String]) throws {
        var rulesPath = "spec/businessid-rules.binpb"
        var lockPath = "rules.lock"
        var outputPath = "Sources/BusinessID/Generated"
        var checkOnly = false

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--rules": rulesPath = try value(arguments, after: &index, of: "--rules")
            case "--lock": lockPath = try value(arguments, after: &index, of: "--lock")
            case "--out": outputPath = try value(arguments, after: &index, of: "--out")
            case "--check": checkOnly = true
            case "--help", "-h":
                print(usage)
                return
            default:
                throw GeneratorFailure(message: "unknown argument \(arguments[index])")
            }
            index += 1
        }

        let bytes = try readFile(rulesPath)

        // The lock attests the bundle before a single byte of it is trusted.
        // An engine verifies the digest of the file it received and never
        // re-serializes a decoded message to recompute one, because Protobuf is
        // not a canonical serialization.
        let lock = try RulesLock(contentsOf: lockPath)
        try lock.verify(rulesBundle: bytes)

        let bundle: LoadedBundle
        do {
            bundle = try RuleBundleLoader.load(bytes)
        } catch {
            throw GeneratorFailure(message: "refusing to generate: \(error)")
        }
        guard bundle.rulesVersion == lock.rulesVersion else {
            throw GeneratorFailure(
                message: "bundle states rules version \(bundle.rulesVersion), "
                    + "rules.lock names \(lock.rulesVersion)"
            )
        }

        let files = SwiftEmitter(bundle: bundle).emit()
        let directory = URL(fileURLWithPath: outputPath, isDirectory: true)

        if checkOnly {
            var stale: [String] = []
            for file in files {
                let path = directory.appending(path: file.name)
                let committed = try? String(contentsOf: path, encoding: .utf8)
                if committed != file.contents { stale.append(file.name) }
            }
            guard stale.isEmpty else {
                throw GeneratorFailure(
                    message: "generated code is out of date: \(stale.joined(separator: ", "))"
                )
            }
            print("businessid-gen: generated code matches \(lock.rulesVersion)")
            return
        }

        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        for file in files {
            try file.contents.write(
                to: directory.appending(path: file.name), atomically: true, encoding: .utf8
            )
        }

        print("businessid-gen: rules \(bundle.rulesVersion), format \(bundle.formatVersion)")
        print("businessid-gen: \(bundle.definitions.count) definitions, \(bundle.dispatchers.count) kinds")
        print(
            "businessid-gen: capabilities \(bundle.requiredFeatures.map(String.init).joined(separator: " "))")
        print("businessid-gen: expansion \(bundle.expansion.summary)")
        print("businessid-gen: wrote \(files.map(\.name).joined(separator: ", ")) to \(outputPath)")
    }

    static func value(_ arguments: [String], after index: inout Int, of flag: String) throws -> String {
        index += 1
        guard index < arguments.count else { throw GeneratorFailure(message: "\(flag) needs a value") }
        return arguments[index]
    }

    static func readFile(_ path: String) throws -> [UInt8] {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw GeneratorFailure(message: "cannot read \(path)")
        }
        return [UInt8](data)
    }

    static let usage = """
        businessid-gen — compiles a LibBusinessID rule bundle to Swift.

          --rules <path>   the bundle to read (default spec/businessid-rules.binpb)
          --lock <path>    the lock attesting it (default rules.lock)
          --out <path>     where to write (default Sources/BusinessID/Generated)
          --check          verify the committed output instead of writing it
        """
}
