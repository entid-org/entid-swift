# Defects found in `spec/` while implementing the Swift engine

Every entry below was found by writing the engine against the documents, not by
reading another engine. Each one names the documents that disagree and the
reading this engine follows. None of them is worked around silently: where a
choice had to be made, it is the one the more recent and argued text states, and
it is marked here so that `spec` can settle it.

The engine passes 676/676 conformance cases under these readings.

---

## Open

### `spec/PROVENANCE.md` is the one file of step 3 the release does not carry

Step 3 makes the engine write `spec/PROVENANCE.md`. Since spec#87 every other
file it names is a release artefact — the bundle, the corpus, the schemas, and
the prose contracts. That one is not, and neither is anything needed to build it.
It has exactly one writer, `tools/write_provenance.sh`, and every input that
writer reads lives in the `spec` checkout: `docs/spec/provenance/body.md`,
`docs/spec/provenance/<lang>.md`, `docs/generated/coverage.md`, and
`go run ./cmd/entidc inspect`. So a workflow that has verified the release
still cannot assemble the file from it, and has to clone `spec` as well — a
second fetch beside the attested one, pinned only by the `sourceCommit` the
attested manifest names.

Which also means no release published so far can be synchronized:
`write_provenance.sh` was added after `v0.1.1` was tagged. Measured on a runner —
[run 32779621303](https://github.com/entid-org/entid-swift/actions/runs/32779621303) — `v0.1.1` passes its sums and all four attestation identities,
and the synchronization then stops because the release it has just verified was
built from a commit with no provenance writer.

**Suggested fix:** publish the assembled per-engine `PROVENANCE.md` as a release
asset, listed in `SHA256SUMS` and covered by the attestation, exactly as the
prose contracts now are. Step 3 would then read only attested bytes, no engine
would need a clone of `spec`, and the file would still have one writer.

**Followed here:** the writer is pinned to the commit the attested manifest
names, exactly as the `Makefile` pins the conformance runner. A release built
before that script existed is refused with the reason printed, rather than given
a second writer — two writers are what made a released engine name `4bf7699` in
its provenance header and `b264614` in its lock.

### `engine.md` numbers two different sections 12.5

`### 12.5 Mutation testing` at line 845 and `## 12.5 Une seule commande,
silencieuse quand tout passe` at line 851. A reference to "section 12.5" is
ambiguous between the two, and this engine now has documentation, a `CLAUDE.md`
and a script citing the second by that number.

The second is also written at `##`, one level above the first, which makes it a
sibling of `## 12. Exigences qualité` rather than one of its subsections — so
structurally it sits outside the section whose number it carries.

**Suggested fix:** renumber the single-command section to `### 12.6`, at the
heading level of its siblings.

**Followed here:** the citations say "section 12.5" and mean the single command,
because that is what the surrounding text is about. Nothing in this engine turns
on the number.

---

## Settled upstream

Kept for the record, because each one changed what this engine does.

### "The newest release" is not `releases/latest` — settled in `engine.md` 11.4

`release.yml` marks every non-stable bundle `--prerelease`, so it stays out of
`releases/latest`, and every release published so far is `alpha`:
`GET /repos/entid-org/spec/releases/latest` answers **404** and
`gh release view` answers "release not found" while `v0.1.1` exists. An engine
that asked the obvious endpoint would have reported nothing to synchronize every
morning until the first stable bundle.

Section 11.4 now says it in as many words: list the releases and take the most
recent that is not a draft. This engine does that, sorted by publication date, so
the 404 is never reached.

### A `prefix_in` may not mix element lengths — settled in `2026.09.2`

Reported from here while making the membership lookup logarithmic. The mixed
length case is the one a per-length search exists for, and the published bundle
cannot exercise it: all four `prefix_in` nodes hold one element length — 1748 of
five, 818 of six, 148 of four, 41 of two — so blocking by length is a no-op on
them and every conformance case passes against a search that mishandles a mixed
table. Four hundred random tables in `PrefixMembershipTests` stood in for the
cases that did not exist.

Rather than leave every engine to re-derive the per-length rule, the bundle may
not carry the shape at all. `PREDICATE_OP_KIND_PREFIX_IN` now states that every
element has the same length, gives the counterexample, and names the spelling a
rule needing two lengths uses: one `prefix_in` per length under an `any`, which
the German court rule already does.

Measured here: `loader-prefix-in-mixed-lengths-040` was **accepted** by this
loader before the check existed, which is what made it the failing test. It is
now refused naming both lengths and the replacement spelling, and four built
shapes are refused alongside it, with a control proving the `any` form is
accepted — so the rule forbids a spelling, not a capability.

### A `WHEN` branch nothing references — settled in `2026.08.31`

`ir.md` section 3.6 has always said `CHECKSUM_OP_KIND_WHEN` "is accepted only as
a direct operand of `CHOOSE`", and check 16 carries it. The reference loader
enforced it by looking at each node's parents, and a node with no parent has
none to look at — section 2 permits an unreachable node — so a `WHEN` nothing
reads passed there. The Kotlin engine read the rule as written and refused it.
Check 16 now says so explicitly, and the program root stays excluded because
`root_node` is a reference: a program rooted in a `WHEN` keeps its own rule and
its own message.

Measured here: this loader required the `CHOOSE` parent to be *present*, not
merely required that no other parent exist, so it already refused a dead branch.
`LoadCheckTests` now pins all three shapes, and the dead-branch case was watched
failing against the parents-only reading, which accepts it.

### `engine.md` section 9.1 contradicted itself — settled in `2026.08.31`

Two sentences: an out-of-bounds view produces an absent value and never an
exception, then an out-of-bounds access in a checksum after a valid format must
produce an engine error. `ir.md` section 1.1 is unreserved — "Absence is never
an error and never an exception" — and the second sentence is gone.

Nothing changed here: the shipped library contains no `fatalError`, no
`precondition` and no `assert`, and every out-of-bounds view yields `.absent`.
`ChecksumOpsTests` now pins the case the deleted clause described, and it was
watched failing against a `ScalarView` that clamps instead of vanishing — which
answers `invalid` where this engine answers `unsupported`.

### The input bound and ill formed text — settled in `2026.08.31`

`ir.md` section 6 step 1 counts UTF-8 bytes and runs before the step that
refuses ill formed input, so an engine whose string type admits such text has to
invent a count. The freedom is now stated, with the obligation to say which
answer was taken.

Swift's `String` admits none, so this engine has no choice to state.
`EncodingTests` already documented that; the documentation is now backed by
normative text rather than by this engine's own reasoning, and a new case pins
the bound at the boundary on `U+FFFD` — three bytes, one code point — from both
sides.

### The JSONL shipped with no digest — settled in `2026.08.26`

`rules.lock` attested seven artefacts. `spec/entid-conformance.jsonl` was
not one of them, and it is the file this engine's tests cite case ids from when
they quote a value: `EngineTests` names the case above every literal, and the
rule in `CONTRIBUTING.md` is that a real value comes from the corpus or from an
issuer, never from memory. A drift between the JSONL and the attested `.binpb`
would have left those citations pointing at the wrong case with nothing
noticing — `verify-lock.sh` had nothing to compare.

Measured before reporting: the vendored JSONL was, and is, byte identical to the
release. The defect was the absence of a check, not a drift.

`rules.lock` now carries `conformance_jsonl_sha256`, taken on the decompressed
bytes that land in `spec/` rather than on the published archive, and `spec.md`
documents the field.

Measured here after the fix: appending one byte to the JSONL makes
`verify-lock.sh` fail and exit 1. `SHA256Tests` derives its list from the lock
rather than repeating it, so a ninth digest fails the suite until it is mapped —
the same defect one level up. And `DocumentedValuesTests` now rests on the
JSONL, which is only defensible because the digest exists.

A note on reading the new field: `conformance_jsonl_sha256` is unchanged between
`2026.08.25` and `2026.08.26` while `conformance_sha256` moved. That is not a
stale file. The JSONL is the reviewed source and carries no rules version — the
generated `.binpb` injects one into every expected report — so a version only
bump changes the binary and not the source. Verified against the `2026.08.26`
release archive, byte for byte.

### `spec.md` permitted embedding the bundle — settled in `2026.08.26`

Found while the digest above was being documented, not by this engine, and
recorded here because it is the more serious of the two. `spec.md` said, in the
section describing `rules.lock`, that an engine MAY embed the bundle if it
chooses to interpret it — which `engine.md` section 1.2 forbids outright and
which this package's `PackagingTests` has always asserted against. It survived
four audits because every mechanical guard read `engine.md` and the per language
contracts and stopped there.

Nothing changed here: this engine never embedded the bundle, and the packaging
suite already refused a `.binpb` under `Sources/`, a `resources:` clause and any
mention of `SwiftProtobuf` in the shipped library.

### Check 16 names the operation categories — settled in `2026.08.26`

`ir.md` section 10 listed check 16 as "accepted root per kind", while section 2
also gives each kind its accepted operation categories, and said nothing about
where that clause runs. Two engines answered differently on the same bytes: one
ran the categories in its per-node pass, ahead of the arithmetic bounds at check
13. Check 16 now names them, "both as section 2 states them".

Measured here: this loader already enforced the categories exhaustively, inside
`ProgramShape`, which runs after the per-program pass — so it answered check 13
first, as section 10 orders. `LoadCheckTests` now pins it on a node that breaks
both at once, and the assertion was watched failing against a loader with the
bound removed, which reports the category instead.

### `loader-left-pad-length-026` refused by two checks its name is not about — settled in `2026.08.25`

The fixture put a `CANONICALIZATION_OP_KIND_LEFT_PAD` node inside the **format**
program and made it the **root** of that program. `ir.md` section 2 gives a
format program the categories string, predicate, assertion and
`CALL_OP_KIND_FORMAT`, and `ASSERTION_OP_KIND_SEQUENCE` as its only accepted
root, so check 16 refused the fixture twice over — before the `length: 4097` its
name is about mattered at all. An engine that never implemented the slice bound
on `left_pad` passed the case.

It could not be repaired in place either: the demo bundle's only
canonicalization program was *also* the dispatcher's pre-canonicalization
program, which `ir.md` section 5 restricts to five steps that do not include
`LEFT_PAD`, so the step had no legal home in the bundle as it stood. The fix had
to add a program, and the first attempt at it traded one refusal for another.

The bundle now carries a second canonicalization program, id 4, referenced by
the definition and not by the dispatcher, rooted in a `SEQUENCE`, holding the
`LEFT_PAD` step alone.

Measured here after the fix, by decoding the payload rather than reading the
description:

| Fixture, modified | Outcome |
|---|---|
| As shipped | refused — `program 4 node 0: length 4097 is outside 0...4096`, the named defect |
| Length repaired to 4096, nothing else | accepted |

So the case now isolates exactly one check, and the fixture moved from the list
of defects with no definable repair into the repair table of
`Tests/EntIDGeneratorTests/FixtureRepairTests.swift`, where the second row
above is the assertion.

### The expansion fixture rooted a checksum program in a string — settled in `2026.08.25`

`loader-program-expansion-036` was wrong twice. It first rooted the doubling
chain in the *format* program; the correction moved the chain into the checksum
program but left `root_node` pointing at the last `CONCAT`, which roots a
checksum program in a `VALUE_TYPE_STRING` and is a check 16 violation. Both
times an engine that counted no instance at all refused the fixture on its shape
and passed the case for the wrong reason.

The chain now feeds a `CHECKSUM_OP_KIND_LUHN` node appended after it, and that
node is the root.

Measured here after the fix: refused with `program 3 expands to 2199023255552
operation instances, beyond the budget of 100000` — forty doublings above a
subject, then the checksum node, so 2^41 against a budget of 100000. The
unreferenced `LUHN` node the fixture still carries at index 1 costs nothing,
which is `ir.md` section 2: a node no root reaches is not emitted.
`Tests/EntIDGeneratorTests/ExpansionTests.swift` pins the reason.

### Where the conformance runner comes from — settled in `2026.08.23`

`spec.md` section 8.7 forbade an engine to judge its own results, and none of
the five contracts said where the runner comes from. No release existed, `spec/`
carried none, and two engines wrote a comparator rather than stop.

`spec.md` section 8.7, `engine.md` section 11.1 and `engine-swift.md` now give
the command, pinned to the commit `rules.lock` records under `source_commit` —
the same commit as the corpus.

This engine's comparator is deleted. Conformance is now the runner's verdict:
`rules 2026.08.23: 666 cases, 666 matched, 0 differed`. The tests that proved
the comparator was not vacuous are kept and re-aimed: they now prove the testee
does not cheat, which `engine.md` section 11.3 requires. That property is
checked by reading the testee's source with comments stripped, and by observing
it answer identically from a directory holding no corpus, under forty borrowed
case identifiers, and in a shuffled order.

### `invalid_encoding` cannot be a conformance case — settled in `2026.08.23`

`ir.md` section 5 step 1 now states it: a proto3 `string` is valid UTF-8 by
definition, and there is no portable malformed value to carry. Each engine pins
the step with a native test naming the malformed form its own string type
admits, and an engine whose string type admits none documents that instead of
widening its public API to reach the branch.

Swift is the third case, and `Tests/EntIDTests/API/EncodingTests.swift`
pins it: `String(bytes:encoding:)` refuses an invalid byte,
`String(decoding:as:)` repairs it to U+FFFD, `Unicode.Scalar(0xD800)` is `nil`,
and the engine reports `invalidEncoding` for none of the awkward inputs that can
be built. A guard also asserts no corpus case asks for the reason.

### The `subject_node` fixture, and check 25 counting it — settled in `2026.08.22`

`loader-subject-node-circular-037` declared `subject_node` while omitting
`CAPTURES_AND_CALLS_V1`, whose frozen content includes it, so check 25 refused
the fixture on its own and the case could not tell an engine implementing check
15's clause from one that never had. The fixture now declares the capability,
and the reference loader now counts `subject_node` towards it rather than
deriving the capability from captures alone.

Measured here after the fix: repairing the circularity — pointing the subject
node at `value()`, not deleting it — makes the fixture load, and removing the
capability again refuses it naming `Program.subject_node`. Both directions are
asserted, because deriving the capability from either construct alone lets the
other through.

### Runtime bundle factories, resources and registry deliverables — settled in `2026.08.18`

`engine.md` section 4 and section 7.2 offered a runtime factory taking a bundle
in bytes, which section 1.2 forbids; `engine-swift.md` both required and forbade
the bundle as a package resource, told the default engine to "load the resource
once", and listed "Protobuf généré" and "interface registre" among the
deliverables against sections 1.2 and 10.4.

All of it is now consistent: the bundle is not a package resource, the default
engine loads nothing, and the deliverables name the generator and the emitted
code with "aucune ressource `.binpb` dans le paquet, aucun type de registre".
This engine already followed sections 1.2 and 10.4 and needed no change.

### Check 14 before check 15 — settled in `2026.08.18`

Check 14 counts from the roots check 15 validates, so running 14 first means
indexing a node array with unvalidated indices. `ir.md` section 2 now states
that an engine may run 15 first, that both answer `invalid_ruleset`, and that
imposing the order would constrain an implementation without changing an answer.

This engine runs 15 then 14, which is now explicitly permitted.

### A `subject_node` built from the subject it defines — settled in `2026.08.18`

`subject()` was defined in terms of itself with nothing forbidding it: a
generator that emits the subject node as a function recurs forever, an
interpreter exhausts its budget, and no check saw it — the node was verified in
scope and in type, never walked.

Check 15 now reads "root, subject and capture nodes inside the program,
correctly typed, and a subject node that does not read the subject it defines".
This engine had already refused it as `invalid_ruleset`; the wording matches what
it does. See open issue 1 for why the accompanying fixture does not yet isolate
the clause.

### Opcode count in `PROVENANCE.md` — settled in `2026.08.18`

The table said `ir.md` documents "The 61 opcodes" where the same file said 63 and
the enumerations of `rules.proto` hold 63. It now says 63.

### `engine.md` section 7.3 lists eighteen load checks

Where `ir.md` section 10 lists twenty five. `engine.md` says itself that its list
is "la vue par famille", so this is a presentation difference rather than a
conflict. No change requested.
