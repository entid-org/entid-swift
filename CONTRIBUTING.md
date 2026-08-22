# Contributing

## What lives here, and what does not

This repository is a **Swift engine**. It holds no business rule.

Rules — which identifiers exist, what shape they take, which checksum they carry
— live in the specification repository and arrive here as an attested artefact.
A pull request that changes a rule belongs there, with its source, its
conformance cases and its false-negative analysis. A pull request here changes
how the engine executes rules, or how the generator compiles them.

Everything under `Sources/BusinessID/Generated` and
`Sources/BusinessIDWire/Generated` is emitted. Never edit it by hand; run
`make generate` or `make proto` and commit the result.

## Before you start

```sh
make help          # every task CI runs
make verify-lock   # the artefacts match rules.lock
make check         # everything a pull request must pass
```

`make check` runs the digests, the formatter, the linter, both build
configurations, the tests, the whole conformance corpus and the stale-generated
check. If it is green locally it will be green in CI.

## Test driven, in that order

The failing test comes first, then the fix. This is not a style preference: a
test written after a fix tends to assert what the fix does rather than what the
defect was, and the two are not the same claim.

For a defect, the first commit — or the first hunk — is the case that fails.
For a new operation, the order is: nominal case, bounds, error, security case,
then the shared conformance corpus.

Watch for a test that passes for the wrong reason. The load-check suite starts
every case from a bundle it first proves is accepted, because three tests once
passed only because the builder itself was refused, which made every expectation
around it succeed vacuously.

## Never write an identifier from memory

Every real value in a test, a fixture or a document comes from the shared
conformance corpus, from an issuer's own published example, or from its
documentation — quoted with its case id in a comment above it.

Seven plausible-looking numbers reached a previous engine this way while its
algorithms were correct. When an algorithm and a number disagree, suspect the
number.

The same rule holds for expected results: never compute one with the code under
test. An arithmetic oracle — a separate tool, a hand computation — is what an
expectation is worth.

## What a change has to answer

A pull request touching the engine or the generator should answer, in its
description:

- **Which common semantics does this affect?** If the answer is "none", say how
  you know.
- **Can the other three engines implement it without diverging?** The contract
  binds observable outputs across Go, Swift, Kotlin and TypeScript.
- **What false-negative risk does it introduce?** Refusing a valid identifier is
  the most serious defect this project recognises. A change that can turn an
  `unsupported` into an `invalid` needs an argument, not a test.
- **Which bounds and hostile inputs are covered?**
- **Does the shared conformance corpus need to change?** If yes, the change
  belongs upstream first.
- **Does the public API stay compatible?** SemVer governs the package;
  `rulesVersion` and `formatVersion` move independently.

An optimisation must show by test that it changes no result. "It is faster" is
not sufficient; `make bench` before and after is.

## Reporting a contradiction rather than working around one

If the specification documents disagree — and they have, eight times so far —
stop and report it. Do not pick a reading quietly.

`SPEC-ISSUES.md` records each one: which documents conflict, which reading this
engine follows, and why. Add to it rather than silently choosing. A contradiction
found and reported has been the most valuable contribution to this project so
far.

## Style

- `swift format` and SwiftLint are both authoritative and both run in CI with
  warnings as errors. `make format` applies the first.
- No `try!`, `as!`, force unwrap or reachable `fatalError` in the library. A
  force unwrap in a test must be local and justified.
- No regular expression interprets a rule. No locale is consulted. No
  `String.count`.
- Comments explain why, not what. A comment restating the line above it is
  noise; a comment naming the defect a guard exists for is the reason the guard
  survives a refactor.
- Every public declaration carries documentation. `swift format` enforces it.

## Commits

Conventional commits (`feat:`, `fix:`, `test:`, `chore:`, `docs:`). English, in
the code, the commits and the documentation. Explain in the body what the change
makes possible or prevents, not which files it touched — the diff already says
that.

**An artefact update is its own commit.** A change under `spec/` or to
`rules.lock`, with the regeneration it implies, goes in a `chore(rules):` commit
and nothing else goes in with it. This is not tidiness: a `git add -A` once swept
a specification update into a commit whose message described a loader, and the
change to the normative documents became invisible to anyone reading the log.
Check `git status` before staging when `spec/` is in the tree.

## Releasing

A release is a SemVer tag. `rulesVersion` is independent: a rules update that
changes no API is a patch of this package.

The release workflow verifies the digests, regenerates from the attested bundle,
requires the working tree to be unchanged by it, runs the whole corpus, and
refuses to publish if anything is red.

A Swift package is distributed as a git tag, not as an uploaded artefact: there
is no binary to sign. What stands in for a signature is the tag itself, so
release tags are signed (`git tag -s`) and protected, and the reproducibility
claim is the regeneration step — the same attested bundle must produce the
committed generated code byte for byte, or the tag ships rules nobody
reviewed.
