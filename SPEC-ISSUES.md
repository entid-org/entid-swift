# Defects found in `spec/` while implementing the Swift engine

Every entry below was found by writing the engine against the documents, not by
reading another engine. Each one names the documents that disagree and the
reading this engine follows. None of them is worked around silently: where a
choice had to be made, it is the one the more recent and argued text states, and
it is marked here so that `spec` can settle it.

The engine passes 666/666 conformance cases under these readings.

---

## Open

### 1. `loader-left-pad-length-026` is refused by two checks its name is not about

The fixture puts a `CANONICALIZATION_OP_KIND_LEFT_PAD` node inside the **format**
program and makes it the **root** of that program. `ir.md` section 2 gives a
format program the categories string, predicate, assertion and
`CALL_OP_KIND_FORMAT`, and `ASSERTION_OP_KIND_SEQUENCE` as its only accepted
root, so check 16 refuses the fixture twice over — before the `length: 4097` its
name is about matters at all.

An engine that never implemented the slice bound on `left_pad` therefore passes
`loader-left-pad-length-026`. It is the same shape as the `subject_node`
fixture, found by the same property once that property was written down.

Measured here:

| Fixture, modified | Outcome |
|---|---|
| As shipped | refused — `length 4097 is outside 0...4096`, the named defect |
| Length repaired to 4096, nothing else | still refused — *a format program roots at an assertion SEQUENCE and nothing else* |
| The node rehoused into a canonicalization program, length left at 4097 | refused — the named defect, in isolation |

The third row is what a repaired fixture should look like, and it also shows why
the fixture was built this way: the demo bundle's only canonicalization program
is *also* the dispatcher's pre-canonicalization program, which `ir.md` section 5
restricts to five steps that do not include `LEFT_PAD`. The step has no legal
home in the bundle as it stands.

**Suggested fix:** give the demo bundle a second canonicalization program, used
by the definition and not by the dispatcher, and put the `left_pad` there. The
case then isolates its defect.

**Followed here:** the fixture is refused, and
`Tests/BusinessIDGeneratorTests/FixtureRepairTests.swift` records exactly which
check answers at each stage, so this engine's compliance does not rest on the
ambiguity. That test fails the day the fixture is fixed, which is the signal to
move it into the repair table with the others.

### 2. `invalid_encoding` is unreachable through a Swift `String` API

`ir.md` section 5 step 1 refuses an input that is not valid UTF-8 with
`unsupported`/`invalid_encoding`. A Swift `String` is always well formed
Unicode, and `TesteeRequest.input` is a proto3 `string`, which is also always
valid UTF-8 on the wire. The corpus still contains no `invalid_encoding` case.

**Followed:** the reason code exists in the public registry and is documented as
unreachable from this API. Adding a byte-oriented entry point purely to reach it
would widen the public surface for a case the protocol cannot deliver. If `spec`
wants the branch exercised, the testee protocol needs a bytes field.

### 3. The conformance runner is not among the artefacts

`spec.md` section 8.7 and `PROVENANCE.md` place the runner in the specification
repository and instruct engines not to write their own suite. The files copied
under `spec/` carry the corpus and the protocol schema but no runner.

**Followed: the instruction, as closely as the artefacts allow.** A runner lives
in this repository under `Sources/BusinessIDConformance`, strictly separated
from the testee: it is the only code that reads an expected result, the testee
never sees one, and neither reaches the shipped library. Its comparison is
proved non-vacuous by cases that alter one field of one response and require the
divergence to be reported. It should be replaced by the reference runner as soon
as that is published.

---

## Settled upstream

Kept for the record, because each one changed what this engine does.

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
