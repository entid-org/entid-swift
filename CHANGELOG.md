# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`rulesVersion` and `formatVersion` move independently of the package version: a
rules update that changes no API is a patch release here.

## [Unreleased]

### Removed

- **The conformance runner written in this repository.** The real one comes
  from the specification repository, pinned to the commit `rules.lock` records
  under `source_commit`, and `spec.md` section 8.7 always forbade an engine to
  judge its own results. It was written here for want of a line saying where to
  get it; that line now exists.

### Changed

- Conformance is now the upstream runner's verdict:
  `rules 2026.08.25: 666 cases, 666 matched, 0 differed`. `make conformance`
  runs it. A Go toolchain in CI is the only new prerequisite, and it is a build
  tool: nothing about it enters the published package or its dependencies.
- The tests that proved the deleted comparator was not vacuous are kept and
  re-aimed at the testee, which `engine.md` section 11.3 now requires: it does
  not read the corpus, does not interpret an expectation, and does not behave
  differently depending on which case it was handed.

- Rules `2026.08.17` → `2026.08.18` → `2026.08.22` → `2026.08.23` → `2026.08.25`.
  Each bundle changed in its business version alone; no rule moved, and the
  regenerated code differs by the one line that carries the version.
- `ir.md` settled two defects this engine reported in `2026.08.18`: check 15
  now carries the clause on a subject node built from the subject it defines,
  worded as this engine already implemented it, and section 2 states that check
  14 may run after check 15. `engine.md` and `engine-swift.md` settled three
  more in the same release and two in `2026.08.22`. None changed an answer here.
- The corpus reaches 666 cases, 35 of them addressed to the generator.
- `loader-subject-node-circular-037` now declares `CAPTURES_AND_CALLS_V1`, so
  the case isolates check 15's clause instead of also being refused by check 25.
- `loader-left-pad-length-026` and `loader-program-expansion-036` were repaired
  upstream in `2026.08.25`, and all three fixtures were re-checked here by
  decoding the payload rather than trusting the description. Each is now refused
  by exactly the check its name is about: the slice bound, check 15's subject
  node clause, and check 14's instance count.
- `TesteeHonestyTests` invents every request it sends. `engine.md` section 11.3
  now states the five observable properties and closes with the constraint the
  suite was breaking: a proof that the testee never opens the corpus, built out
  of the corpus, demonstrates the opposite of what it asserts. What the corpus
  itself carries moved to `CorpusShapeTests`, and a guard fails if the honesty
  suite reaches for a corpus reader again.
- Check 25 now names which construct reaches for `CAPTURES_AND_CALLS_V1`,
  `Program.captures` or `Program.subject_node`, because deriving the capability
  from either alone lets the other through — the defect the reference loader
  carried.

### Added

- `EncodingTests` pins `ReasonCode.invalidEncoding` natively, as `ir.md`
  section 5 step 1 now requires: Swift's `String` admits neither an invalid
  byte nor an unpaired surrogate, so the branch is unreachable through this API
  and no byte-oriented entry point is added to reach it.
- `TesteeHonestyTests` checks the testee's source with comments stripped, and
  observes it answering identically from a directory holding no corpus, under
  eleven case identifiers — plausible, absurd and empty — and in a shuffled
  order. The requests are written in the suite, not read from the corpus.
- `FixtureRepairTests` states the property every hostile fixture should have:
  repair the defect its name carries — repair, not erase — and the bundle
  loads. Eighteen of the thirty five loader fixtures are covered; the rest are
  named with the reason no repair is definable.
- That property found `loader-left-pad-length-026` on its first run: the
  fixture put a canonicalization node in a format program and rooted the
  program at it, so an engine with no `left_pad` bound passed the case anyway.
  Reported upstream and fixed in `2026.08.25`; the fixture is now in the repair
  table, and `SPEC-ISSUES.md` has nothing open.
- `ExpansionTests` pins why `loader-program-expansion-036` is refused: the
  count, not the program shape. The fixture had been wrong twice about that.

### Fixed

- `SubjectNodeTests` no longer proves its point by clearing `subject_node`.
  Erasing the construct removed the circularity and the missing capability
  together, so the test passed against the fixture it was written to accuse.
  It now repairs the subject node instead.
- An interrupted `Tools/mutation.sh` left a mutant applied. Restoration is a
  trap, and the script refuses to start on a dirty tree.
- Luhn's reduction of a doubled digit was no longer pinned by a unit test. The
  mutation gate caught it: `digit > 9` and `digit > 10` differ for one digit
  only — five, whose double reaches exactly ten — and every Luhn case in the
  suite used a doubled digit of four or less. The corpus covered it until the
  in-repository runner was deleted and the corpus left `swift test`. Mutation
  score back to 14/14.
- The iOS job could not have passed. Deleting the in-repository conformance
  runner left `-only-testing:BusinessIDConformanceTests` naming a target that no
  longer exists, and left `BusinessIDTesteeTests` — which drives a subprocess —
  compiled for a simulator that has no `Process`. The target is now compiled out
  anywhere but macOS, and the job runs the library suite: 111 tests in 11 suites.

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
