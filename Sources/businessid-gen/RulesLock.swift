import BusinessIDGenerator
import CryptoKit
import Foundation

/// `rules.lock`, the only point of coupling between this engine and the
/// specification repository.
///
/// It names a release and attests its content. It says nothing about the
/// language or the implementation strategy.
struct RulesLock {
    let rulesVersion: String
    let formatVersion: Int
    let digests: [String: String]

    init(contentsOf path: String) throws {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw Generate.GeneratorFailure(message: "cannot read \(path)")
        }
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            fields[key] = value
        }
        guard let version = fields["rules_version"], !version.isEmpty else {
            throw Generate.GeneratorFailure(message: "\(path) states no rules_version")
        }
        rulesVersion = version
        formatVersion = fields["format_version"].flatMap(Int.init) ?? 0
        digests = fields
    }

    /// Verifies the SHA-256 of the file received, never of a re-serialized
    /// message.
    func verify(rulesBundle bytes: [UInt8]) throws {
        guard let expected = digests["rules_sha256"], !expected.isEmpty else {
            throw Generate.GeneratorFailure(message: "rules.lock states no rules_sha256")
        }
        let actual = SHA256.hash(data: Data(bytes))
            .map { String(format: "%02x", $0) }
            .joined()
        guard actual == expected else {
            throw Generate.GeneratorFailure(
                message: "bundle digest \(actual) does not match the locked \(expected)"
            )
        }
    }
}
