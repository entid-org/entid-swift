import BusinessID

// Everything below is the whole public surface a consumer needs. There is no
// setup, no bundle to load and nothing to configure: the rules were compiled
// into the package when it was built.

let engine = BusinessIDEngine.default
print("rules \(engine.rulesVersion), IR format \(engine.formatVersion), engine \(engine.engineVersion)")

let info = engine.rulesInfo()
print("\(info.identifierCount) definitions across \(info.countryCount) countries")

// A validation.
//
// Every identifier below is synthetic, produced by the generator of
// DATA_POLICY.md section 4, and names the conformance case it comes from.
// `engine.md` section 12.2.1: an example demonstrates an API, not what a
// register issues, so a synthetic value is the right one — and it has to say
// that it is one.
//
// `siren-validate-format-050` is the value `012345674`; the separators here
// are the printed form, which is what this line is about.
let report = engine.validate(IdentifierInput(kind: "siren", value: "  012 345-674 "))
print("")
print("input      \(report.inputValue.debugDescription)")
print("canonical  \(report.canonicalValue)")
print("country    \(report.countryCode ?? "-")")
print("format     \(report.format.status.rawValue) / \(report.format.reasonCode.rawValue)")
print("checksum   \(report.checksum.status.rawValue) / \(report.checksum.reasonCode.rawValue)")

// Not knowing is a result. A format this project validates whose checksum its
// authority has never published reports `unsupported`, never `invalid`.
// `cegjegyzekszam-hu-valid-001`.
let unpublished = engine.validate(IdentifierInput(kind: "cegjegyzekszam", value: "0123456789"))
print("")
print("format valid:     \(unpublished.isFormatValid)")
print("checksum valid:   \(unpublished.isChecksumValid)")
print("fully validated:  \(unpublished.isFullyValidated)")
print("invalid:          \(unpublished.isInvalid)")
print("checksum reason:  \(unpublished.checksum.reasonCode.rawValue)")

// The format alone, when the checksum is not wanted. `lei-canonicalize-020`.
let lei = IdentifierInput(kind: "lei", value: "0000-0000-0000-0000-0098")
let formatOnly = engine.validateFormat(lei)
print("")
print("format only: \(formatOnly.format.status.rawValue)")
print("checksum:    \(formatOnly.checksum.reasonCode.rawValue)")

// An unknown kind is a result too, not an error.
let unknown = engine.validate(IdentifierInput(kind: "no_such_kind", value: "X"))
print("unknown kind: \(unknown.format.status.rawValue) / \(unknown.format.reasonCode.rawValue)")

precondition(report.isFullyValidated, "the corpus value must validate")
precondition(!unpublished.isInvalid, "an unpublished checksum is never an invalidity")
print("")
print("consumer: ok")
