# Defects found in `spec/` while implementing the Swift engine

Every entry below was found by writing the engine against the documents, not by
reading another engine. Each one names the documents that disagree and the
reading this engine follows. None of them is worked around silently: where a
choice had to be made, it is the one the more recent and argued text states,
and it is marked here so that `spec` can settle it.

The engine passes 665/665 conformance cases under these readings.

## 1. `engine.md` still offers a runtime bundle factory that section 1.2 forbids

- **Section 4** lists "chargement optionnel d'un bundle fourni en mémoire" in
  the V1 scope.
- **Section 7.2** says "Le moteur PEUT permettre la construction depuis des
  bytes."
- **Section 1.2** and `engine-swift.md` forbid exactly that: a custom ruleset
  goes through the generator, at build time, and no engine exposes a factory
  taking a bundle at runtime.

Sections 4 and 7.2 are residue of the interpreter-era text; section 1.2 is the
argued rewrite and section 15.1 already records that the operation list had not
been updated. **Followed: section 1.2.** No such API exists in this package.

## 2. `engine-swift.md` both requires and forbids the bundle as a package resource

- **Line 26**: "Le bundle et la conformité sont des ressources SPM accessibles
  via `Bundle.module`."
- **Line 53**: "Aucun `.binpb` n'est une ressource du paquet."
- **Lines 113-115** repeat the first reading: "Le moteur par défaut doit charger
  la ressource une fois."

**Followed: line 53.** Neither `.binpb` is a package resource. The rules bundle
is an input of the generator; the conformance corpus is read from `spec/` by the
test targets, which are not shipped.

## 3. `engine-swift.md` asks for deliverables sections 1.2 and 10 exclude

- **Line 138**: "Code généré [Protobuf] sous `Sources/BusinessID/Generated`."
  The Protobuf code belongs to the generator, which is the only target that
  decodes anything. It lives in `Sources/BusinessIDWire` here.
- **Lines 248-249**: "Livrer … ressources, Protobuf généré, interface registre."
  `engine.md` section 10.4 says the opposite about the registry: expose no
  registry type at all, even experimental.

**Followed: sections 1.2 and 10.4.** No registry type is public, no validation
method is asynchronous, and the core package has no HTTP dependency.

## 4. Check 14 cannot run before check 15, as the stated order requires

`ir.md` section 10 lists check 14 (expansion) before check 15 (root, subject and
capture nodes inside the program and correctly typed). But check 14 counts from
"the program root, the `subject_node` when the program declares one, and every
capture no other root reaches" — the exact node indices check 15 validates.
Running 14 first would mean indexing a node array with unvalidated indices.

**Followed: 15 then 14.** Both report `invalid_ruleset`, so the swap is not
observable through the testee protocol. The ordering that *is* observable — the
version and capability checks before the unknown field scan — is respected
exactly.

## 5. A `subject_node` whose subtree reads `subject()` is not forbidden

`ir.md` section 2 says `Program.subject_node` "produces `subject()` for a top
level invocation", and section 3.1 says `SUBJECT` yields "the caller supplied
view for a called program, otherwise `Program.subject_node`". If the subtree
rooted at `subject_node` itself contains `STRING_OP_KIND_SUBJECT`, then
`subject()` is defined in terms of itself.

No reading makes such a bundle usable: a generator that emits the subject node
as a function recurs forever, and an interpreter exhausts its step budget. It is
not covered by any of the twenty five checks.

**Followed: refused as `invalid_ruleset`**, as part of check 15. The published
bundle declares no `subject_node` at all, so nothing observable changes; a
future bundle would be refused rather than crash a generator. `spec` should
state this explicitly, in check 15 or in section 2.

## 6. `invalid_encoding` is unreachable through a Swift `String` API

`ir.md` section 5 step 1 refuses an input that is not valid UTF-8 with
`unsupported`/`invalid_encoding`. A Swift `String` is always well formed
Unicode, and `TesteeRequest.input` is a proto3 `string`, which is also always
valid UTF-8 on the wire. The corpus contains no `invalid_encoding` case.

**Followed: the reason code exists in the public registry and is documented as
unreachable from this API.** Adding a byte-oriented entry point purely to reach
it would widen the public surface for a case the protocol cannot deliver. If
`spec` wants the branch exercised, the testee protocol needs a bytes field.

## 7. Minor: counts stated inconsistently

- `PROVENANCE.md` line 35 says `ir.md` documents "The 61 opcodes"; line 25 of
  the same file says 63, and the enumerations in `rules.proto` hold 63.
- The engine prompt states 33 `load_ruleset` cases; the corpus holds 34.
- `engine.md` section 7.3 lists eighteen load checks where `ir.md` section 10
  lists twenty five. `engine.md` says itself that its list is "la vue par
  famille", so this is a presentation difference rather than a conflict.

**Followed: the artefacts.** 63 opcodes, 34 loader cases, 25 checks.

## 8. The conformance runner is not among the artefacts

`spec.md` section 8.7 and `PROVENANCE.md` place the runner in the specification
repository and instruct engines not to write their own suite. The files copied
under `spec/` here carry the corpus and the protocol schema but no runner.

**Followed: the instruction, as closely as the artefacts allow.** A runner lives
in this repository under `Sources/BusinessIDConformance`, strictly separated
from the testee: it is the only code that reads an expected result, the testee
never sees one, and neither reaches the shipped library. Its comparison is
proved non-vacuous by cases that alter one field of one response and require the
divergence to be reported. It should be replaced by the reference runner as soon
as that is published.
