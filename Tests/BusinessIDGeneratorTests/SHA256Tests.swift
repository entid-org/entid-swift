import Foundation
import Testing

@testable import BusinessIDGenerator

/// The digest is checked against an oracle this package did not write.
///
/// The first three vectors are the FIPS 180-4 examples. The rest are the seven
/// artefacts `rules.lock` attests, whose digests were produced by a separate
/// tool: if the implementation below were wrong, it would have to be wrong in
/// exactly the way that tool is.
@Suite("SHA-256")
struct SHA256Tests {
    private func digest(_ text: String) -> String { SHA256.hexDigest([UInt8](text.utf8)) }

    @Test("The FIPS 180-4 vectors")
    func fipsVectors() {
        #expect(
            digest("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        #expect(
            digest("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        #expect(
            digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
                == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
    }

    @Test("A message spanning several blocks and every padding boundary")
    func paddingBoundaries() {
        // 55, 56 and 64 bytes are the three shapes padding has to get right:
        // the last block that still fits the length, the one that does not, and
        // an exact multiple of the block size.
        #expect(
            digest(String(repeating: "a", count: 55))
                == "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"
        )
        #expect(
            digest(String(repeating: "a", count: 56))
                == "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"
        )
        #expect(
            digest(String(repeating: "a", count: 64))
                == "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"
        )
        #expect(
            digest(String(repeating: "a", count: 1_000_000))
                == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
        )
    }

    /// Every `*_sha256` field of `rules.lock`, mapped to the file it attests.
    ///
    /// The mapping is checked against the lock rather than trusted, because the
    /// defect this guards against is a digest nobody verifies:
    /// `conformance_jsonl_sha256` did not exist until `2026.08.26`, the JSONL
    /// shipped unattested, and the engine tests cite its case ids as
    /// provenance. A ninth field added upstream must fail here until it is
    /// mapped, instead of being silently skipped.
    static let attested: [String: String] = [
        "rules_sha256": "businessid-rules.binpb",
        "conformance_sha256": "businessid-conformance.binpb",
        "conformance_jsonl_sha256": "businessid-conformance.jsonl",
        "rules_proto_sha256": "rules.proto",
        "conformance_proto_sha256": "conformance.proto",
        "testee_proto_sha256": "testee.proto",
        "ir_doc_sha256": "ir.md",
        "features_doc_sha256": "features.md",
    ]

    static func lockFields() throws -> [String: String] {
        let lock = try String(
            contentsOf: SpecCorpus.root.appending(path: "rules.lock"), encoding: .utf8
        )
        var fields: [String: String] = [:]
        for line in lock.split(separator: "\n") where line.hasSuffix("\"") {
            let parts = line.split(separator: "\"")
            guard parts.count == 2, let name = parts[0].split(separator: " ").first else { continue }
            fields[String(name)] = String(parts[1])
        }
        return fields
    }

    @Test("The lock states no digest this test does not verify")
    func everyDigestIsCovered() throws {
        let stated = Set(try Self.lockFields().keys.filter { $0.hasSuffix("_sha256") })
        #expect(
            stated == Set(Self.attested.keys),
            Comment(rawValue: "unmapped: \(stated.subtracting(Self.attested.keys).sorted())")
        )
    }

    @Test("Every artefact rules.lock attests digests to the value it states")
    func attestedArtefacts() throws {
        let fields = try Self.lockFields()
        for (field, file) in Self.attested.sorted(by: { $0.key < $1.key }) {
            #expect(
                SHA256.hexDigest(try SpecCorpus.specFile(file)) == fields[field],
                Comment(rawValue: file)
            )
        }
    }

    @Test("A digest is thirty two bytes")
    func digestLength() {
        #expect(SHA256.digest([]).count == 32)
        #expect(SHA256.digest([UInt8](repeating: 7, count: 1000)).count == 32)
    }
}
