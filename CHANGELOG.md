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

- **The rules version moves backwards, from `2026.09.2` to `2026.08.32`.**
  `PATCH` in `YYYY.MM.PATCH` is a counter within a month with no upper bound,
  and four versions had announced September while still in August. Measured
  here before accepting it: nothing in this repository compares versions for
  order. All five comparisons are equality — the generator against the lock, the
  corpus against the lock, the engine against the lock, and two in tests — and
  the only code that looks at the version's structure asserts it has three
  dot-separated components, which `2026.08.32` satisfies.


- Conformance is now the upstream runner's verdict:
  `rules 2026.08.33: 676 cases, 676 matched, 0 differed`. `make conformance`
  runs it. A Go toolchain in CI is the only new prerequisite, and it is a build
  tool: nothing about it enters the published package or its dependencies.
- The tests that proved the deleted comparator was not vacuous are kept and
  re-aimed at the testee, which `engine.md` section 11.3 now requires: it does
  not read the corpus, does not interpret an expectation, and does not behave
  differently depending on which case it was handed.

- Rules `2026.08.17` → `2026.08.18` → `2026.08.22` → `2026.08.23` → `2026.08.25`
  → `2026.08.26` → `2026.08.31` → `2026.09.0` → `2026.09.1` → `2026.09.2`
  → `2026.08.32` → `2026.08.33`. Every bundle but
  `2026.08.31` changed in its business version alone; no rule moved in those,
  and the regenerated code differs by the one line that carries the version.
- **The `prefix_in` element length is measured in UTF-8 bytes**, which is the
  unit `ir.md` states — not the unit that would suit this engine's search. `PZ`
  and `é` are both two bytes and are not both two code points, so a table this
  loader must accept can still reach the search as two blocks. Reading the rule
  in code points would have refused that table and accepted `["PZ", "éé"]`,
  which is two code points each and two bytes against four; both directions are
  pinned, and both fail under the code point reading.

  No conformance case separates the two readings — every element of the
  published bundle is ASCII, where they agree — so this is pinned natively, as
  is the per-length search semantics itself: since `2026.08.32` `ir.md` states
  that the mixed-length refusal takes its own evidence with it and that an
  engine MUST pin the semantics below its loader. The four hundred random tables
  of `PrefixMembershipTests` were already doing that by this engine's own
  judgement; they now satisfy a stated requirement.

- **A `prefix_in` may not mix element lengths**, refused since `2026.09.2` and
  now refused here. This engine reported the gap that led to the rule: the
  published bundle cannot prove the mixed-length reasoning, because all four of
  its `prefix_in` nodes hold one element length — 1748 of five, 818 of six, 148
  of four, 41 of two — so blocking by length is a no-op on them and every
  conformance case passes against a search that mishandles a mixed table.

  The reason is correctness, not speed: over one sorted list of mixed lengths a
  search for the greatest element not after the value answers wrongly, since
  `["AB", "ABA"]` against `"ABCD"` finds `ABA`, which is not a prefix, while
  `AB` is. At one length, starting with an element is equalling its opening of
  that length. A rule needing two lengths writes one `prefix_in` per length
  under an `any`, and the refusal message says so.

  `loader-prefix-in-mixed-lengths-040` was accepted here before the check
  existed, which is what made it the failing test. It joins the fixtures with no
  definable repair for the same reason as the alphabet family: bringing two
  values of different lengths to one length invents a value, and dropping one
  erases half the construct.

  `PrefixMembershipTests` keeps its four hundred random mixed tables even though
  the loader now refuses the shape they exercise. The load check and the search
  are two pieces of code that can drift apart, and the suite is what notices if
  the first is relaxed while the second still assumes it.

- **The declared order of `prefix_in` values was already enforced here**, which
  `ir.md` section 9 has always stated and check 13 has named since `2026.09.1`.
  The reference loader was not enforcing it, and the omission is invisible while
  a lookup is a scan — a scan of an unsorted list is merely slow. It becomes
  load bearing the moment the lookup is a binary search.

  Measured rather than asserted, by enumerating permutations of
  `["AA", "BB", "CC", "DD"]`: `["AA", "BB", "DD", "CC"]` against `"CCX"` makes
  the search answer false where a scan answers true. So an unsorted list is not
  answered slowly but wrongly, and `Predicates.prefixIn` now records that its
  correctness rests on a precondition the loader checks.

  All three shapes the reference loader let through — descending, duplicated,
  and equal keys out of order — are now asserted on both parameter lists, with
  a control that the same lists in order are accepted. The corpus fixture
  carries the first only, and this suite covered descending lengths alone.

- **A membership test is no longer linear in the size of the list**, which
  `engine.md` section 14 asks for as of `2026.09.0`. `Predicates.prefixIn` was
  `prefixes.contains { view.hasPrefix($0) }`; the register memberships made that
  visible, because the cost falls on the refused input, which has to rule out
  every entry before answering.

  The generator now emits a membership table sorted by length first and code
  points second, so every prefix of one length is a contiguous ordered block,
  and the predicate binary searches each block for the view's own prefix of that
  length. Measured end to end, on the German court table of 1748 + 818 codes:

  | | scan | blocked search |
  | --- | --- | --- |
  | absent court | 7083 ns | 3411 ns |
  | present court | 4148 ns | 3755 ns |
  | probes, absent, 1748 entries | 1748 | 20 |
  | probes, absent, 818 entries | 818 | 18 |

  A single binary search over the whole table would have been wrong, not merely
  slow: with `["A", "AA"]` and the value `"ABC"` the greatest entry not
  exceeding the value is `"AA"`, which is not a prefix, while `"A"` is. The
  differential test caught exactly that on `"1BBA"` against a table holding
  `"1"`.

- **`2026.08.31` is the first release to move a rule.** Three memberships were
  added — 148 French greffe codes, 2566 German XJustiz court codes split by
  length, and a Luxembourg section letter constrained to being a letter rather
  than to `B` — and the corpus grew from 666 to 673 cases. Conformant with no
  engine change: the lists are data the bundle carries, and the generator
  compiles them. Measured here: bundle 99 677 → 120 872 bytes, emitted Swift
  392 042 → 418 425 bytes, total nodes 2376 → 2386, expansion 3069 → 3094
  instances across the same 250 programs, worst program unchanged at 152/118.
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
- **Coverage no longer gates the code emitted from the bundle.** `engine.md`
  section 12.2 now says the thresholds cover hand written code, and that the
  emitted code's coverage measures the corpus rather than the engine: gating on
  it would fail a faultless engine on a corpus gap, and the only way back to
  green would be to lower the threshold. Three numbers are printed, two gated.
  Removing 19879 emitted lines from the denominator moved the published figures
  down: hand written library 97.73% (was 99.25% with the emitted code folded
  in), hand written package 96.99% (was 98.92%), emitted rule code 99.31%.
- The README and the example consumer state that every identifier they print is
  synthetic and name the conformance case it comes from, which `engine.md`
  section 12.2.1 now requires. A synthetic value proves an algorithm; a real one
  proves a rule describes what a register issues, and a README demonstrates
  neither register nor company.
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

- **`make verify`, the single entry point `engine.md` section 12.5 requires.**
  It runs the lock digests, the regenerated code, both build configurations, the
  tests, the conformance corpus judged by the runner from `spec`, lint, format,
  coverage against its thresholds, the dependency audit, the fuzz smoke run, the
  example consumer and the iOS simulator. It prints **one line** when everything
  passes, the failing step's name and that step's output and nothing else when
  one does not, and exits non-zero the moment a step fails.

  CI calls the same script, so "green" never has two definitions: eleven jobs
  became one `verify` job, plus two that are not subsets of it — the minimum
  toolchain, which is a different Swift rather than a different set of steps,
  and the Protobuf round trip, which needs tools the engine's verification has
  no reason to require. The release workflow calls it too.

  The rule lives in `CLAUDE.md`, which section 12.5 asks for: it addresses
  whoever runs, not whoever reads.

  Its failure path was written wrong first and caught before it was trusted:
  `if ! "$@"` makes `$?` the status of the negation, which is always zero, so a
  failing step would have exited **zero**. The status is now taken from the
  command itself, and the comment says why.


- `PrefixMembershipTests`: a differential test comparing the search against the
  loop it must be equivalent to over four hundred random tables, a probe budget
  standing in for a timing, and the same budget on the tables actually shipped.
  The published bundle cannot prove any of it — its three membership tables hold
  one length each, so the blocking is a no-op on them and every conformance case
  passes against a search that mishandles a mixed table.
- Two benchmarks aimed at a membership miss, which `engine.md` section 14 asks
  for and this set did not have: both existing early-rejection benchmarks stop
  at dispatch and never reach a list.
- `FixtureRepairTests` pins `loader-when-unreferenced-038`, the corpus case the
  `WHEN`-outside-`CHOOSE` clause had lacked entirely, to the rule it names
  rather than to `invalid_ruleset` alone.
- `FixtureRepairTests` also pins `loader-prefix-in-unsorted-039` and repairs it:
  sorting the values makes the bundle load, which is what proves the fixture
  carries one defect and not two. The corpus reaches 676 cases, 38 of them
  addressed to the generator.


- `LoadCheckTests` pins `CHECKSUM_OP_KIND_WHEN` as accepted **only** as a direct
  operand of `CHOOSE`, including the branch nothing references at all. The
  reference loader read the rule through each node's parents, and a node with no
  parent has none — `ir.md` section 2 permits an unreachable node, so a dead
  `WHEN` passed there. This loader required the `CHOOSE` parent to be present
  rather than merely required no other parent, so it already refused one; the
  test now says so, and fails against the parents-only reading.
- `ChecksumOpsTests` pins an out-of-bounds access inside a checksum as an
  absence. `engine.md` section 9.1 contradicted itself in two sentences until
  `2026.08.31` — an absent value and never an exception, then an engine error
  after a valid format — and the clause is gone. This engine never had it: no
  `fatalError`, `precondition` or `assert` exists in the shipped library.
- `EncodingTests` pins the input bound as UTF-8 bytes at the boundary, from both
  sides, on `U+FFFD` — three bytes and one code point, so the two readings of
  `ir.md` section 6 step 1 separate on it. That step now states the freedom an
  engine whose string type admits ill formed text has, and requires it to say
  which answer it took; Swift's `String` admits none, so there is nothing to
  choose and the suite says why.


- **`rules.lock` carries an eighth digest, `conformance_jsonl_sha256`.** The
  JSONL shipped under `spec/` with nothing attesting it while the engine tests
  cite its case ids as provenance, so a drift would have passed unseen.
  `verify-lock.sh` verifies it, and `SHA256Tests` now derives its list from the
  lock instead of repeating it: a ninth field added upstream fails the suite
  until it is mapped, rather than being silently skipped.
- `DocumentedValuesTests` reads `README.md` and the example consumer and
  requires every identifier printed there to be a synthetic corpus value and
  every case id cited to exist. It rests on the JSONL, which is only worth
  resting on now that a digest attests it.
- `LoadCheckTests` pins the order of `ir.md` section 10 on a node that breaks
  check 13 and check 16 at once: thirteen answers. Two engines disagreed here
  because one ran the operation categories in the per-node pass; since
  `2026.08.26` check 16 names the categories, so which check answers is stated
  rather than incidental.


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
  anywhere but macOS, and the job runs the library suite, measured green on a
  simulator. The count is left to the run rather than written here: a number
  in prose goes stale on the next test added, which is how a job name came to
  claim 665 cases against a corpus of 666.

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
