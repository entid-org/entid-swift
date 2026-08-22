/// The family of identifier being validated.
///
/// This is an extensible string value type rather than a closed enum. A caller
/// may hold a token this release has never heard of — a newer kind, a typo, a
/// value read from a database — and the engine must report `unsupportedKind`
/// for it rather than fail to represent it.
public struct IdentifierKind: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension IdentifierKind: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { rawValue = value }
}

extension IdentifierKind: CustomStringConvertible {
    public var description: String { rawValue }
}
