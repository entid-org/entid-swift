# ``EntID``

Offline validation of company identifiers: VAT numbers, national registration
numbers, LEI, EUID and more.

## Overview

`EntID` answers two questions about an identifier and refuses to imply a
third.

- **Is the format valid?** The shape is compatible with a documented variant.
- **Is the checksum valid?** The documented internal check is satisfied.
- **Does the company exist?** This library does not answer that, here or
  anywhere in this version. No registry is consulted.

```swift
import EntID

let report = EntIDEngine.default.validate(
    IdentifierInput(kind: "vat", value: "BE 0123.456.749")
)

report.canonicalValue    // "BE0123456749"
report.format.status     // .valid
report.checksum.status   // .valid
```

### Not knowing is a result

Where no documented rule applies, the answer is ``StepStatus/unsupported``,
never ``StepStatus/invalid``. Refusing a valid identifier is the most serious
defect this project recognises, and turning an absence of knowledge into a
rejection is how it happens.

This is why there is no `isValid` on ``ValidationReport``. A format that
validates with a checksum its authority has never published is neither fully
validated nor invalid:

```swift
let report = engine.validate(IdentifierInput(kind: "cegjegyzekszam", value: "0123456789"))

report.isFormatValid       // true
report.isChecksumValid     // false
report.isFullyValidated    // false
report.isInvalid           // false
report.checksum.reasonCode // .checksumNotPublished
```

### The rules are compiled, not interpreted

This engine holds no rule bundle and interprets nothing at runtime. A generator
reads the attested bundle when the package is built and emits Swift; what ships
is that emitted code, a small set of primitives, and this API. There is
therefore no initializer taking a bundle: a custom ruleset goes through the
generator, at build time.

### Concurrency

``EntIDEngine`` is a `Sendable` value with no stored property. Sharing it
across tasks needs no lock, and every operation is synchronous — permanently.
Registry lookup, when it arrives, will be a separate asynchronous operation in a
separate module, never a mode of these.

## Topics

### Validating

- ``EntIDEngine``
- ``IdentifierInput``
- ``IdentifierKind``
- ``ValidationOptions``
- ``ValidationProfile``

### Reading a result

- ``ValidationReport``
- ``CanonicalizationResult``
- ``StepResult``
- ``StepStatus``
- ``ReasonCode``
- ``ValidationLevel``

### Inspecting the rules

- ``RulesInfo``
