#!/usr/bin/env bash
# Targeted mutation testing.
#
# `engine.md` section 12.5 asks for mutation testing where the ecosystem allows
# it. No stable tool exists for Swift packages, so the mutants below are applied
# by hand to the places where a wrong answer would be invisible: the checksum
# arithmetic, the position comparisons and the bounds. A surviving mutant is a
# test that does not test what it claims to.
set -uo pipefail
cd "$(dirname "$0")/.."

# Each mutant must change an answer. A mutant that cannot — padding by zero, a
# bound moved where no value can land — is not evidence about the tests, so it
# is not listed here: it would survive forever and say nothing.
#
# file:from:to
MUTANTS=(
  "Sources/BusinessID/Runtime/ChecksumOps.swift:if digit > 9 { digit -= 9 }:if digit > 10 { digit -= 9 }"
  "Sources/BusinessID/Runtime/ChecksumOps.swift:return total.isMultiple(of: 10) ? .valid : .invalid(messageKey):return total.isMultiple(of: 11) ? .valid : .invalid(messageKey)"
  "Sources/BusinessID/Runtime/ChecksumOps.swift:scalars.count >= 2:scalars.count >= 1"
  "Sources/BusinessID/Runtime/ChecksumOps.swift:scalars.count >= 3:scalars.count >= 2"
  "Sources/BusinessID/Runtime/ChecksumOps.swift:return remainder == 1 ? .valid:return remainder == 0 ? .valid"
  "Sources/BusinessID/Runtime/IntegerOps.swift:guard let value, value >= 0, value <= modulus else { return nil }:guard let value, value >= 0 else { return nil }"
  "Sources/BusinessID/Runtime/IntegerOps.swift:guard let value, value >= 0, value < Int64(values.count) else { return nil }:guard let value, value >= 0 else { return nil }"
  "Sources/BusinessID/Runtime/IntegerOps.swift:for index in 0..<min(mapped.count, weights.count) {:for index in 0..<mapped.count {"
  "Sources/BusinessID/Runtime/ScalarView.swift:guard let storage, start <= end, end <= storage.count else { return .absent }:guard let storage, start <= end, end <= storage.count + 1 else { return .absent }"
  "Sources/BusinessID/Runtime/ScalarView.swift:guard let storage, offset >= 0, offset < storage.count else { return nil }:guard let storage, offset >= 0, offset <= storage.count else { return nil }"
  "Sources/BusinessID/Runtime/CanonicalizationSteps.swift:value.insert(contentsOf: repeatElement(pad, count: length - value.count), at: 0):value.insert(contentsOf: repeatElement(pad, count: length - value.count), at: value.count)"
  "Sources/BusinessID/Runtime/CanonicalizationSteps.swift:guard index <= value.count else { return }:guard index < value.count else { return }"
  "Sources/BusinessID/API/Pipeline.swift:guard input.value.utf8.count <= inputByteLimit else {:guard input.value.count <= inputByteLimit else {"
  "Sources/BusinessID/Runtime/Whitespace.swift:case 0x0009...0x000D, 0x0020: true:case 0x0009...0x000D: true"
)

killed=0
survived=0
for mutant in "${MUTANTS[@]}"; do
  file=${mutant%%:*}
  rest=${mutant#*:}
  from=${rest%%:*}
  to=${rest#*:}

  cp "$file" "$file.original"
  # Substitute literally, not as a pattern.
  python3 - "$file" "$from" "$to" <<'PY'
import sys, pathlib
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
text = p.read_text()
if old not in text:
    print(f"MUTANT NOT APPLICABLE in {path}: {old}", file=sys.stderr)
    sys.exit(2)
p.write_text(text.replace(old, new, 1))
PY
  status=$?
  if [ $status -ne 0 ]; then
    mv "$file.original" "$file"
    echo "  ERROR   $file :: $from"
    survived=$((survived + 1))
    continue
  fi

  if swift test --quiet >/dev/null 2>&1; then
    echo "  SURVIVED $file :: $from -> $to"
    survived=$((survived + 1))
  else
    echo "  killed   $file :: $from -> $to"
    killed=$((killed + 1))
  fi
  mv "$file.original" "$file"
done

total=$((killed + survived))
echo ""
echo "mutation score: $killed/$total killed"
[ "$survived" -eq 0 ]
