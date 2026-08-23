# Defects found in `spec/` while implementing the Swift engine

Every entry below was found by writing the engine against the documents, not by
reading another engine. Each one names the documents that disagree and the
reading this engine follows. None of them is worked around silently: where a
choice had to be made, it is the one the more recent and argued text states, and
it is marked here so that `spec` can settle it.

The engine passes 666/666 conformance cases under these readings.

---

## Open

Nothing open. Every defect reported from this engine has been settled upstream;
the record is below.

---

## Settled upstream

Kept for the record, because each one changed what this engine does.

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
`Tests/BusinessIDGeneratorTests/FixtureRepairTests.swift`, where the second row
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
`Tests/BusinessIDGeneratorTests/ExpansionTests.swift` pins the reason.

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

Swift is the third case, and `Tests/BusinessIDTests/API/EncodingTests.swift`
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
