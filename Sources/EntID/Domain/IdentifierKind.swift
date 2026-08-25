/// The family of identifier being validated.
///
/// This is an extensible string value type rather than a closed enum. A caller
/// may hold a token this release has never heard of — a newer kind, a typo, a
/// value read from a database — and the engine must report `unsupportedKind`
/// for it rather than fail to represent it.
public struct IdentifierKind: RawRepresentable, Sendable, Hashable, Codable {
    /// The token as the caller wrote it, before any normalization.
    public let rawValue: String

    /// Wraps a token, whether or not this release knows it.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Wraps a token, whether or not this release knows it.
    public init(_ rawValue: String) { self.rawValue = rawValue }

    /// Decodes from a bare JSON string.
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    /// Encodes as a bare JSON string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension IdentifierKind: ExpressibleByStringLiteral {
    /// Wraps a literal, so that `let kind: IdentifierKind = "siren"` reads.
    public init(stringLiteral value: String) { rawValue = value }
}

extension IdentifierKind: CustomStringConvertible {
    /// The token itself.
    public var description: String { rawValue }
}
