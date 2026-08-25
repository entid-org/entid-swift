#!/usr/bin/env bash
# Verifies every digest `rules.lock` attests, and that the schemas the generator
# compiles against are byte for byte the ones of the same release.
#
# `rules.lock` is the only point of coupling between this engine and the
# specification repository. It names a release and attests its content; nothing
# is read from `spec/` before this passes.
set -euo pipefail
cd "$(dirname "$0")/.."

digest() { shasum -a 256 "$1" | cut -d' ' -f1; }
locked() { grep -E "^$1 = " rules.lock | sed -E 's/.*"(.*)".*/\1/'; }

fail=0
check() {
  local name=$1 path=$2 expected actual
  expected=$(locked "$name")
  actual=$(digest "$path")
  if [ "$expected" = "$actual" ]; then
    printf '  ok    %-32s %s\n' "$(basename "$path")" "$name"
  else
    printf '  FAIL  %-32s expected %s, got %s\n' "$(basename "$path")" "$expected" "$actual"
    fail=1
  fi
}

echo "rules.lock names $(locked rules_version), format version $(grep -E '^format_version' rules.lock | tr -d ' ' | cut -d= -f2)"
check rules_sha256 spec/entid-rules.binpb
check conformance_sha256 spec/entid-conformance.binpb
# The JSONL is shipped decompressed, so the digest is taken on what lands in
# spec/ rather than on the archive the release publishes. It went unlisted
# until 2026.08.26: nothing verified the file the engine tests cite case ids
# from, and a drift would have passed unseen.
check conformance_jsonl_sha256 spec/entid-conformance.jsonl
check rules_proto_sha256 spec/rules.proto
check conformance_proto_sha256 spec/conformance.proto
check testee_proto_sha256 spec/testee.proto
check ir_doc_sha256 spec/ir.md
check features_doc_sha256 spec/features.md

# The generator compiles against copies under proto/, which protoc needs in a
# package shaped tree. They must be the attested files and not a fork of them.
for pair in "rules.proto:proto/libbusinessid/ir/v1/rules.proto" \
            "conformance.proto:proto/libbusinessid/conformance/v1/conformance.proto" \
            "testee.proto:proto/libbusinessid/testee/v1/testee.proto"; do
  source_file="spec/${pair%%:*}"
  copy="${pair##*:}"
  if cmp -s "$source_file" "$copy"; then
    printf '  ok    %-32s matches %s\n' "$(basename "$copy")" "$source_file"
  else
    printf '  FAIL  %-32s differs from %s\n' "$(basename "$copy")" "$source_file"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "the artefacts do not match rules.lock; do not generate from them" >&2
fi
exit $fail
