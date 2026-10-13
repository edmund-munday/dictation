#!/usr/bin/env bash
# Verify every L-marked requirement has a test, and every test names an R-ID.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQ="$ROOT/docs/requirements/dictation/02-requirements.md"
TEST_DIR="$ROOT/Tests"

if [[ ! -f "$REQ" ]]; then
  echo "error: requirements file not found: $REQ" >&2
  exit 1
fi

L_IDS="$(
  python3 - "$REQ" <<'PY'
import re, sys
path = sys.argv[1]
ids = []
with open(path) as f:
    for line in f:
        m = re.match(r"\|\s*(R\d+)\s*\|[^|]*\|[^|]*\|\s*([^|]+)\|", line)
        if m and re.search(r"\bL\b", m.group(2)):
            ids.append(m.group(1))
print("\n".join(ids))
PY
)"

TEST_NAMES="$(
  rg -o --no-filename 'func (test_R[0-9]+[A-Za-z0-9_]*)\s*\(' "$TEST_DIR" || true
)"

TEST_RIDS="$(
  printf '%s\n' "$TEST_NAMES" | sed -n 's/.*\(R[0-9][0-9]*\).*/\1/p' | sort -u
)"

fail=0

echo "== L R-IDs missing a test =="
missing=0
while IFS= read -r rid; do
  [[ -z "$rid" ]] && continue
  if ! printf '%s\n' "$TEST_NAMES" | grep -q "test_${rid}"; then
    echo "  MISSING: $rid"
    missing=$((missing + 1))
    fail=1
  fi
done <<< "$L_IDS"
if [[ "$missing" -eq 0 ]]; then
  echo "  (none)"
fi

echo "== Tests whose names lack an R-ID =="
bad=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  name="${line#func }"
  name="${name%%(*}"
  name="$(echo "$name" | tr -d ' ')"
  if ! [[ "$name" =~ ^test_R[0-9]+ ]]; then
    echo "  BAD: $name"
    bad=$((bad + 1))
    fail=1
  fi
done <<< "$TEST_NAMES"
# Also flag any XCTest method not matching test_R*
OTHER="$(rg -o --no-filename 'func (test_[A-Za-z0-9_]+)\s*\(' "$TEST_DIR" || true)"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  name="${line#func }"
  name="${name%%(*}"
  name="$(echo "$name" | tr -d ' ')"
  if [[ "$name" == test_* ]] && ! [[ "$name" =~ ^test_R[0-9]+ ]]; then
    echo "  BAD: $name"
    bad=$((bad + 1))
    fail=1
  fi
done <<< "$OTHER"
if [[ "$bad" -eq 0 ]]; then
  echo "  (none)"
fi

echo "== Summary =="
l_count="$(printf '%s\n' "$L_IDS" | grep -c '^R' || true)"
t_count="$(printf '%s\n' "$TEST_NAMES" | grep -c 'test_R' || true)"
echo "  L requirements: $l_count"
echo "  tests with R-ID: $t_count"
echo "  unique R-IDs in tests: $(printf '%s\n' "$TEST_RIDS" | grep -c '^R' || true)"

if [[ "$fail" -ne 0 ]]; then
  echo "check-rids: FAILED" >&2
  exit 1
fi
echo "check-rids: OK"
