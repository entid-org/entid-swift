#!/usr/bin/env bash
# The single entry point `engine.md` section 12.5 requires.
#
#   success: one line, carrying the numbers that matter and nothing else
#   failure: the output of the failing step and only that, preceded by its name
#   non-zero exit as soon as a step fails, never swallowed
#
# The reason is not aesthetic. A resync round run as thirty commands puts thirty
# full outputs through the context of whoever drives it, twenty-nine of which say
# only "this passes". A command that stays silent when everything is fine makes
# complete verification cheaper than partial verification.
#
# CI calls this too, so "green" never has two definitions.
#
# Not here: mutation, the long fuzz and the benchmarks. They run on their own
# cadence in .github/workflows/scheduled.yml, and mutation rewrites files in
# place and refuses a dirty tree, which would make this unusable while working.
# `make mutation`, `make fuzz` and `make bench` run them.
set -uo pipefail
cd "$(dirname "$0")/.."

LOG_DIR=".build/verify"
mkdir -p "$LOG_DIR"

step() {
  local name=$1
  shift
  local log="$LOG_DIR/${name//[^a-zA-Z0-9]/-}.log"
  local code
  # Not `if ! "$@"`: inside that branch `$?` is the status of the negation,
  # which is always zero, and the failure would exit zero. The point of this
  # script is that a failure is never swallowed, so the status is taken from
  # the command itself. And `local code` on its own line, because `local` with
  # an assignment would overwrite `$?` before it is read.
  "$@" >"$log" 2>&1
  code=$?
  if [ "$code" -ne 0 ]; then
    printf 'verify: %s failed\n\n' "$name" >&2
    cat "$log" >&2
    exit "$code"
  fi
}

# A value read out of a step's own output, so the summary quotes what ran
# rather than recomputing it a second way.
from() { sed -n "$1" "$LOG_DIR/$2.log"; }

step "lock digests"        ./Tools/verify-lock.sh
step "format"              swift format lint -r -s -p Sources Tests Package.swift
step "lint"                swiftlint lint --strict --quiet
step "build debug"         swift build
step "build release"       swift build -c release
step "generated code"      swift run businessid-gen --rules spec/businessid-rules.binpb \
                             --lock rules.lock --out Sources/BusinessID/Generated --check
step "tests"               swift test
step "conformance"         make conformance
step "coverage"            ./Tools/coverage.sh
step "fuzz smoke"          swift run -c release businessid-fuzz --rounds 20000
step "dependency audit"    bash -c 'swift package resolve && swift package show-dependencies --format json | python3 Tools/audit-dependencies.py'
step "consumer package"    bash -c 'cd Examples/BusinessIDConsumer && swift build && swift run BusinessIDConsumer'
step "ios simulator"       make ios

RULES=$(sed -n 's/^rules_version = "\(.*\)"/\1/p' rules.lock)
TESTS=$(from 's/.*Test run with \([0-9]*\) tests.*/\1/p' tests | tail -1)
CASES=$(from 's/.*: \([0-9]*\) cases, \([0-9]*\) matched.*/\2\/\1/p' conformance | tail -1)
LIBRARY=$(from 's/^hand written library line coverage: \([0-9.]*\)%.*/\1/p' coverage)
PACKAGE=$(from 's/^hand written package line coverage: \([0-9.]*\)%.*/\1/p' coverage)
EMITTED=$(from 's/^emitted rule code line coverage: *\([0-9.]*\)%.*/\1/p' coverage)
# What a consumer compiles: the shipped library and nothing else.
SHIPPED=$(find Sources/BusinessID -name '*.swift' -exec cat {} + | wc -c | tr -d ' ')

printf 'verify: rules %s, %s tests, %s conformance, coverage %s/%s gated %s emitted, shipped %s KiB\n' \
  "$RULES" "$TESTS" "$CASES" "$LIBRARY" "$PACKAGE" "$EMITTED" "$((SHIPPED / 1024))"
