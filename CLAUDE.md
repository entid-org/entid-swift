# Working in this repository

## Verify with one command

```sh
make verify
```

That is the whole verification: lock digests, regenerated code, both build
configurations, the tests, the shared conformance corpus judged by the runner
from `spec`, lint, format, coverage against its thresholds, the dependency
audit, the fuzz smoke run, the example consumer, and the iOS simulator.

Its contract, from `engine.md` section 12.5:

- **it succeeds silently** — one line, carrying the numbers that matter;
- **it fails loudly and narrowly** — the name of the failing step and that
  step's output, nothing else;
- **it exits non-zero the moment a step fails.**

So do not run the steps one by one to see them pass. Thirty commands put thirty
full outputs through the context of whoever is driving, twenty-nine of which say
only "this passes". One command that stays quiet makes complete verification
cheaper than partial verification, which is the point.

CI calls the same script, so "green" never has two definitions.

Individual targets still exist (`make test`, `make lint`, `make conformance`,
`make help`) — for working on one thing, not for checking the whole.

## What `verify` deliberately leaves out

`make mutation`, `make fuzz` (the long run) and `make bench` run on their own
cadence, in `.github/workflows/scheduled.yml`. Mutation rewrites files in place
and refuses a dirty tree, which would make `verify` unusable while working.

CI runs two more jobs beside it, and neither is a subset of it: the minimum
toolchain, which is a different Swift and not a different set of steps, and the
Protobuf round trip, which needs `protoc` and a built `protoc-gen-swift` that
the engine's own verification has no reason to require.

## A single line is not a single measurement

`verify` prints durations nowhere, on purpose. A benchmark that looks like a
regression is a benchmark to repeat: a run once showed a membership lookup
2.9x slower until the untouched baseline turned out to have moved with it. The
properties this engine holds are counted, not timed — probe counts, case counts,
line counts — and the durations belong in a report as context.

## Rules that bite while running

- **`spec/` is vendored, never edited here.** It is copied from the
  specification repository at the commit `rules.lock` records under
  `source_commit`, and every artefact is attested by a digest. A problem in it
  is reported upstream, not patched locally.
- **Nothing is read from `spec/` before `verify-lock` passes.**
- **Never write an identifier from memory.** Every real value in a test, a
  fixture or a document comes from the shared corpus, from an issuer's published
  example, or from its documentation, quoted with its case id in a comment above
  it. `DocumentedValuesTests` checks the documents; nothing checks your memory.
- **The failing test comes first.** A guard that has not been watched failing has
  not been tested — including a guard that prints nothing, which reads exactly
  like a guard that found nothing.
- **No tag, no release**, unless asked in so many words.
