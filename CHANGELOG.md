# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`rulesVersion` and `formatVersion` move independently of the package version: a
rules update that changes no API is a patch release here.

## [Unreleased]

### Changed

- Rules `2026.08.17` → `2026.08.18` → `2026.08.22`. Each bundle changed in its
  business version alone; no rule moved, and the regenerated code differs by
  the one line that carries the version.
- `ir.md` settled two defects this engine reported in `2026.08.18`: check 15
  now carries the clause on a subject node built from the subject it defines,
  worded as this engine already implemented it, and section 2 states that check
  14 may run after check 15. `engine.md` and `engine-swift.md` settled three
  more in the same release and two in `2026.08.22`. None changed an answer here.
- The corpus reaches 666 cases, 35 of them addressed to the generator.
- `loader-subject-node-circular-037` now declares `CAPTURES_AND_CALLS_V1`, so
  the case isolates check 15's clause instead of also being refused by check 25.
- Check 25 now names which construct reaches for `CAPTURES_AND_CALLS_V1`,
  `Program.captures` or `Program.subject_node`, because deriving the capability
  from either alone lets the other through — the defect the reference loader
  carried.

### Added

- `FixtureRepairTests` states the property every hostile fixture should have:
  repair the defect its name carries — repair, not erase — and the bundle
  loads. Seventeen of the thirty five loader fixtures are covered; the rest are
  named with the reason no repair is definable.
- That property found `loader-left-pad-length-026` on its first run: the
  fixture puts a canonicalization node in a format program and roots the
  program at it, so an engine with no `left_pad` bound passes the case anyway.
  Reported upstream as `SPEC-ISSUES.md` open issue 1.

### Fixed

- `SubjectNodeTests` no longer proves its point by clearing `subject_node`.
  Erasing the construct removed the circularity and the missing capability
  together, so the test passed against the fixture it was written to accuse.
  It now repairs the subject node instead.
- An interrupted `Tools/mutation.sh` left a mutant applied. Restoration is a
  trap, and the script refuses to start on a dirty tree.

## [0.1.0]

First engine. Rules `2026.08.17`, IR format version `1`.

### Added

- `BusinessIDEngine` with `canonicalize`, `validate`, `validateFormat`,
  `validateChecksum`, `rulesInfo` and `capabilities`. All synchronous, and
  permanently so.
- Coverage of 94 identifier definitions across 37 countries and 37 kinds: VAT,
  LEI, EUID, SIREN, SIRET, CNPJ, USCC, EIN, DUNS, EORI and twenty seven national
  registration numbers.
- `businessid-gen`, the build-time generator. It reads the attested rule bundle,
  applies the twenty five load checks of `ir.md` section 10 and emits Swift.
  Nothing it needs at build time ships to a consumer.
- `businessid-testee`, the conformance testee, speaking the published wire
  protocol over stdin and stdout.
- Codable conformance on every public result type, using the field names and the
  lower case enum spellings of the common model.

### Conformance

- 665/665 shared conformance cases, zero divergences, in process and over the
  wire protocol.
- All 34 `load_ruleset` cases refused with the typed error the runner expects.
- Expansion profile of the published bundle: 250 programs, 3069 instances, worst
  program 152 at 118.

### Quality

- Line coverage 99.25% in the shipped library, 98.64% across the package.
- Mutation score 14/14 on the checksum arithmetic, the position comparisons and
  the bounds.
- Zero warnings from the compiler in debug and release, from `swift format` and
  from SwiftLint.
- The shipped library has no dependency.

### Reported upstream

Eight contradictions found in the specification while implementing, recorded in
`SPEC-ISSUES.md`, including one defect no load check covers: a `subject_node`
whose subtree reads `subject()` defines `subject()` in terms of itself, and is
refused here as `invalid_ruleset`.
