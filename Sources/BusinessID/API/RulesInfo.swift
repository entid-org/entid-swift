/// What the compiled rules cover.
public struct RulesInfo: Sendable, Hashable, Codable {
    /// Business version of the rules, `YYYY.MM.PATCH`.
    public let rulesVersion: String
    /// Structural version of the IR they were compiled from.
    public let formatVersion: Int
    /// Version of this package. It moves independently of the two above.
    public let engineVersion: String
    /// How many identifier definitions the rules carry.
    public let identifierCount: Int
    /// How many distinct countries those definitions cover.
    public let countryCount: Int
    /// The canonical kinds this engine dispatches, sorted.
    public let kinds: [IdentifierKind]

    public init(
        rulesVersion: String,
        formatVersion: Int,
        engineVersion: String,
        identifierCount: Int,
        countryCount: Int,
        kinds: [IdentifierKind]
    ) {
        self.rulesVersion = rulesVersion
        self.formatVersion = formatVersion
        self.engineVersion = engineVersion
        self.identifierCount = identifierCount
        self.countryCount = countryCount
        self.kinds = kinds
    }
}

/// Version of this package, following SemVer independently of the rules.
public let engineVersion = "0.1.0"
