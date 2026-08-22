# Security

## Reporting

Report a vulnerability privately through GitHub's security advisory form on this
repository, or to the maintainers listed in `CONTRIBUTING.md`. Please do not open
a public issue for anything exploitable.

Include what you did, what happened, and what you expected. A reproducing input
is worth more than a description: every surface here is deterministic, so a
seed, a byte sequence or an identifier is enough to reproduce a finding exactly.

Expect an acknowledgement within a week and an assessment within two.

## What is in scope

This package has two surfaces that read input someone else chose.

**The engine**, which reads a caller's string. It must never trap, hang or
allocate without a bound on any input, valid UTF-8 or not, of any length. A
crash reachable from a validated string is a vulnerability, not a bug report.

**The generator**, which reads a rule bundle at build time. It must refuse every
malformed or hostile artefact rather than emit code from it. A generator that
crashes on a forged bundle is a supply chain problem; one that *accepts* a forged
bundle is worse, because the result is code nobody reviewed.

Out of scope: the correctness of a business rule. A rule that accepts or refuses
the wrong identifier is a defect of the rules, which live in the specification
repository, and is reported there.

## Threat model

The threats this package is designed against, and the answer to each:

| Threat | Answer |
|---|---|
| Forged or corrupted bundle | Digest checked against `rules.lock` before the bytes are read; the twenty five load checks refuse anything the schema does not permit |
| A bundle omitting the capability matching what it uses | Check 25 computes the capabilities actually used and refuses an omission, so the omission cannot read as permission |
| Size or depth bomb | Every structural limit is enforced at load; the expansion check refuses a graph that expands beyond the budget once operands are inlined |
| Integer overflow | Every accumulation is checked and reports indeterminate; the generator proves the bounds at load so an accepted ruleset cannot reach one |
| Unicode disagreement between runtimes | The frozen whitespace table and the ASCII classes are written out and never delegated |
| ReDoS | There is no regular expression anywhere in this package |
| Rule cycle | The call graph is proved acyclic with a static depth of at most 32 |
| Checksum run on an unvalidated value | The format is a mandatory guard; there is no API that reaches a checksum without it |
| An unbounded input | 1024 UTF-8 bytes, refused before processing |

## What this package does not defend against

It makes **no claim about existence**. A validating identifier may belong to no
one, and using this library as an anti-fraud control on its own is a misuse of
it. Existence requires a registry, which this version does not consult.

It performs **no network access** of any kind, so it cannot be used as a
side channel — and equally, it cannot tell you whether a number was revoked.

## Rules, revocation and updates

Rules are attested artefacts, not code this repository writes. A rules update
arrives as a change to `rules.lock` alone, and regeneration verifies every
digest before emitting anything. If a published rules release has to be
withdrawn, this repository reverts `rules.lock` to the previous release,
regenerates, and publishes a patch; the advisory names the affected digest.

## Hardening notes for consumers

- The library holds no state and opens no file. Sandboxing it needs no
  exemption.
- `BusinessID` links no dependency. SwiftPM still resolves `swift-protobuf`,
  which belongs to the generator and the conformance tooling; nothing a
  consumer builds links it, and `Tools/audit-dependencies.py` fails CI if a
  second name appears in the resolved graph.
- `businessid-gen`, `businessid-testee`, `businessid-fuzz` and
  `businessid-bench` are development tools. None of them is reachable from the
  `BusinessID` library product, and a consumer never builds them.
- If you accept identifiers from untrusted sources, note that the 1024-byte
  bound applies to the raw input; bounding your own field before calling costs
  nothing and fails earlier.
