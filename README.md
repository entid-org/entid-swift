# BusinessID

Offline validation of company identifiers — VAT numbers, national registration
numbers, LEI, EUID and thirty four other kinds — for Swift.

```swift
import BusinessID

// `vat-be-normalization-004`. Synthetic, produced by the generator of
// DATA_POLICY.md section 4 — it designates no company, and none is needed
// here: a README example demonstrates an API, not what a register issues.
let report = BusinessIDEngine.default.validate(
    IdentifierInput(kind: "vat", value: "BE 0123.456.749")
)

report.canonicalValue    // "BE0123456749"
report.countryCode       // "BE"
report.format.status     // .valid
report.checksum.status   // .valid
```

Rules version `2026.09.2`: **94 definitions across 37 countries**, 37 identifier
kinds, and the full shared conformance corpus of **676 cases** passing.

## What this answers, and what it does not

This library answers two questions and refuses to imply a third.

- **`format valid`** — the shape is compatible with a documented variant.
- **`checksum valid`** — the documented internal check is satisfied.
- **Existence is not answered.** No registry is consulted, here or anywhere in
  this version. A number that validates may belong to no one.

There is deliberately no `isValid` on a report. A format that validates with a
checksum its authority has never published is neither fully validated nor
invalid, and a single boolean would have to lie about one of the two:

```swift
// `cegjegyzekszam-hu-valid-001`, synthetic like the one above.
let report = engine.validate(IdentifierInput(kind: "cegjegyzekszam", value: "0123456789"))

report.isFormatValid      // true
report.isChecksumValid    // false
report.isFullyValidated   // false
report.isInvalid          // false  ← not knowing is not a rejection
report.checksum.reasonCode // .checksumNotPublished
```

### Not knowing is a result

Where no documented rule applies, the answer is `unsupported`, never `invalid`.
Refusing a valid identifier is the most serious defect this project recognises,
and turning an absence of knowledge into a rejection is how it happens. An
unknown kind, a country with no rule, an unpublished checksum algorithm — each
is reported as what it is.

Every identifier printed in this README is **synthetic** and names the
conformance case it is quoted from. `engine.md` section 12.2.1 and
`DATA_POLICY.md` section 3 separate the two demonstrations: a synthetic value
proves an algorithm, a real one proves that a rule describes what a register
issues. This file demonstrates an API, so synthetic is the correct choice — and
a value written from memory is neither, and is forbidden everywhere.

## Installation

```swift
.package(url: "https://github.com/libbusinessid/businessid-swift.git", from: "0.1.0")
```

```swift
.product(name: "BusinessID", package: "businessid-swift")
```

Requires Swift 6.1. Declared for macOS 13+, iOS 16+, tvOS 16+ and watchOS 9+;
CI builds and tests on macOS with the current toolchain and with Swift 6.1, and
runs the library suite on an iOS simulator. The conformance corpus is not run
there: the runner drives the testee as a subprocess, which a simulator has no
`Process` for, so that target is compiled out anywhere but macOS rather than
skipped at run time.

**The `BusinessID` library links nothing.** No Protobuf, no HTTP, no UIKit, no
AppKit; the binary of a consumer carries none of them. SwiftPM does still
*resolve* this package's whole manifest, so `swift-protobuf` is fetched into
`.build/checkouts` — it belongs to `businessid-gen` and the conformance
tooling, which are separate targets a consumer never builds and never links.
`Tools/audit-dependencies.py` fails CI if a second name ever appears there.

## The four operations

All four are synchronous, and will stay synchronous.

```swift
let engine = BusinessIDEngine.default

engine.canonicalize(input)      // normalize only, no rule runs
engine.validate(input)          // format, then checksum
engine.validateFormat(input)    // format only; checksum reports not_run/not_requested
engine.validateChecksum(input)  // exactly what validate returns, named for the call site
engine.rulesInfo()              // versions, coverage, kinds
engine.capabilities()           // the frozen capability ids the rules require
```

`validateChecksum` exists for readability, not to skip the format: a checksum is
never run on a value whose format was not validated.

### The profile is optional, and its absence means something

```swift
engine.validate(input)                                            // the definition's own default
engine.validate(input, options: .init(profile: .compatible))      // accept documented historical variants
engine.validate(input, options: .init(profile: .strictCurrent))   // only currently issued variants
```

Leaving the profile out is not the same as asking for `compatible`: it is what
lets a definition apply its own default. An API that filled it in would make
that default unreachable.

## No bundle at runtime

This engine does not interpret rules at runtime. It is not a virtual machine.

A **generator** runs when the library is built: it reads the attested rule
bundle, applies the twenty five load checks of the specification, and emits
Swift. What ships is that emitted code, a small set of primitives it calls, and
this API. There is no Protobuf decoder, no IR interpreter and no `.binpb` in the
package.

```
spec/businessid-rules.binpb ──▶ businessid-gen ──▶ Sources/BusinessID/Generated/*.swift
        (attested input)         (25 checks)              (committed, reviewable)
```

The generated code is committed, so building this package — as a consumer or in
CI — needs no network and no access to the specification repository.
Regeneration is a maintainer's deliberate act:

```sh
make verify-lock   # every digest rules.lock attests
make generate      # recompile the bundle to Swift
make generated-check   # fail if the committed output is stale
```

Consequently there is **no initializer taking a bundle at runtime**. A custom
ruleset goes through the generator, at build time.

## Concurrency

`BusinessIDEngine` is a `Sendable` value with no stored property. Sharing it
across tasks needs no lock and no `@unchecked` escape hatch, because there is
nothing to protect. Every public type is `Sendable`; nothing is cached between
calls; no global is mutable.

```swift
await withTaskGroup(of: ValidationReport.self) { group in
    for input in inputs { group.addTask { BusinessIDEngine.default.validate(input) } }
}
```

## Unicode and bounds

- Positions and lengths are counted in **Unicode code points**, never in
  grapheme clusters and never in UTF-16 units. `String.count` counts grapheme
  clusters and is used nowhere in this package.
- Whitespace is the frozen `whitespace_v1` table, written out. It is never
  delegated to the platform's Unicode tables, whose versions differ.
- Uppercasing maps only `a...z` and consults no locale.
- Raw input is bounded at **1024 UTF-8 bytes**. A longer input is refused
  without being processed, reported as `unsupported`/`inputTooLong` — a safety
  bound, never a business verdict.

`ReasonCode.invalidEncoding` stays in the registry and is unreachable through
this API. Every engine pins that step with a native test naming the malformed
form its own string type admits — an invalid byte where strings are bytes, an
unpaired surrogate where they are UTF-16 code units. Swift's `String` admits
neither: `String(bytes:encoding:)` refuses an invalid byte, `String(decoding:)`
repairs it to U+FFFD, and `Unicode.Scalar(0xD800)` is `nil`. Adding a
byte-oriented entry point that existed only to reach the branch would widen the
public API to serve a reason code rather than a caller.

## Registry lookup: not in this version

There is no registry type in this package, not even an experimental one. A
public type is a commitment SemVer freezes.

What is decided now is the shape of the hole: local validation stays synchronous
permanently, `validate` will never call a registry, and a lookup — which carries
an API token and must never be possible from a browser — will arrive in a
separate, server-only module when it is specified.

## Documentation

```sh
make docs        # DocC archive for the BusinessID target
make help        # every task CI runs
```

- [`SPEC-ISSUES.md`](SPEC-ISSUES.md) — contradictions found in the specification
  while implementing, and the reading this engine follows for each.
- [`SECURITY.md`](SECURITY.md) — threat model, reporting, rule revocation.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — what a change has to answer.

## Conformance

Conformance is not a suite rewritten in Swift, and it is not this package's
verdict to give. The **runner** comes from the specification repository, pinned
to the commit `rules.lock` records under `source_commit` — the same commit as
the corpus, so a corpus can never be judged by another release's comparator:

```sh
make conformance   # rules 2026.09.2: 676 cases, 676 matched, 0 differed
```

which is

```sh
go run github.com/libbusinessid/spec/cmd/conformance-runner@<source_commit> \
  -corpus spec/businessid-conformance.binpb -- .build/debug/businessid-testee
```

A Go toolchain in CI is the only prerequisite. It is a build tool: nothing about
it enters the published package or its dependencies.

What this package writes is the **testee** — an executable that reads requests,
calls the public API and writes responses — and the tests proving it does not
cheat. It does not read the corpus, does not interpret an expected result, and
does not behave differently depending on which case it was handed; each of those
is a test, both by reading its source and by observing it answer identically
from a directory holding no corpus, under a borrowed case identifier, and in a
shuffled order.

There is deliberately no comparator here. An engine that judges its own results
can declare itself conformant by comparing too weakly — forgetting a field, or
treating an absent field as an empty one.

The thirty five `load_ruleset` cases address the generator rather than the
engine: a truncated bundle, one carrying a call cycle, or one whose subject node
is built from the subject it defines must make generation fail. The rest address
the engine over the wire protocol.

## Verifying the rules you got

Every digest in `rules.lock` is checked before a byte of the bundle is trusted:

```sh
./Tools/verify-lock.sh
```

The generator verifies the digest of the file it received and never
re-serializes a decoded message to recompute one, because Protobuf is not a
canonical serialization.

## Licence

Apache-2.0. See [`LICENSE`](LICENSE).
