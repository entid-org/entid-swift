/// SHA-256, FIPS 180-4.
///
/// The generator verifies the digest of the file it received against
/// `rules.lock` before it trusts a single byte of it. It never re-serializes a
/// decoded message to recompute one, because Protobuf is not a canonical
/// serialization and the digest would then attest the decoder rather than the
/// artefact.
///
/// It is implemented here rather than taken from CryptoKit so that the whole
/// package builds on every platform Swift supports, including the ones where a
/// maintainer might regenerate. It is checked against the FIPS 180-4 vectors
/// and against the seven artefacts `rules.lock` attests, whose digests come
/// from an independent tool.
package enum SHA256 {
    private static let roundConstants: [UInt32] = [
        0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5, 0x3956_C25B, 0x59F1_11F1,
        0x923F_82A4, 0xAB1C_5ED5, 0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3,
        0x72BE_5D74, 0x80DE_B1FE, 0x9BDC_06A7, 0xC19B_F174, 0xE49B_69C1, 0xEFBE_4786,
        0x0FC1_9DC6, 0x240C_A1CC, 0x2DE9_2C6F, 0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA,
        0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7, 0xC6E0_0BF3, 0xD5A7_9147,
        0x06CA_6351, 0x1429_2967, 0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC, 0x5338_0D13,
        0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85, 0xA2BF_E8A1, 0xA81A_664B,
        0xC24B_8B70, 0xC76C_51A3, 0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070,
        0x19A4_C116, 0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5, 0x391C_0CB3, 0x4ED8_AA4A,
        0x5B9C_CA4F, 0x682E_6FF3, 0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208,
        0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7, 0xC671_78F2,
    ]

    /// The digest of a byte sequence, as thirty two bytes.
    package static func digest(_ message: [UInt8]) -> [UInt8] {
        var state: [UInt32] = [
            0x6A09_E667, 0xBB67_AE85, 0x3C6E_F372, 0xA54F_F53A,
            0x510E_527F, 0x9B05_688C, 0x1F83_D9AB, 0x5BE0_CD19,
        ]

        var padded = message
        let bitCount = UInt64(message.count) &* 8
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            padded.append(UInt8(truncatingIfNeeded: bitCount >> UInt64(shift)))
        }

        var schedule = [UInt32](repeating: 0, count: 64)
        for blockStart in stride(from: 0, to: padded.count, by: 64) {
            for index in 0..<16 {
                let offset = blockStart + index * 4
                schedule[index] =
                    UInt32(padded[offset]) << 24 | UInt32(padded[offset + 1]) << 16
                    | UInt32(padded[offset + 2]) << 8 | UInt32(padded[offset + 3])
            }
            for index in 16..<64 {
                let first = schedule[index - 15]
                let second = schedule[index - 2]
                let s0 = rotate(first, 7) ^ rotate(first, 18) ^ (first >> 3)
                let s1 = rotate(second, 17) ^ rotate(second, 19) ^ (second >> 10)
                schedule[index] = schedule[index - 16] &+ s0 &+ schedule[index - 7] &+ s1
            }

            var (a, b, c, d) = (state[0], state[1], state[2], state[3])
            var (e, f, g, h) = (state[4], state[5], state[6], state[7])

            for index in 0..<64 {
                let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
                let choice = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ choice &+ roundConstants[index] &+ schedule[index]
                let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ majority

                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            state[0] &+= a
            state[1] &+= b
            state[2] &+= c
            state[3] &+= d
            state[4] &+= e
            state[5] &+= f
            state[6] &+= g
            state[7] &+= h
        }

        var result: [UInt8] = []
        result.reserveCapacity(32)
        for word in state {
            for shift in stride(from: 24, through: 0, by: -8) {
                result.append(UInt8(truncatingIfNeeded: word >> UInt32(shift)))
            }
        }
        return result
    }

    /// The digest as sixty four lower case hexadecimal characters, which is how
    /// `rules.lock` and the release manifest spell one.
    package static func hexDigest(_ message: [UInt8]) -> String {
        let alphabet = Array("0123456789abcdef")
        var out = ""
        out.reserveCapacity(64)
        for byte in digest(message) {
            out.append(alphabet[Int(byte >> 4)])
            out.append(alphabet[Int(byte & 0x0F)])
        }
        return out
    }

    private static func rotate(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
