#!/usr/bin/env bash
# Verify every remaining L-marked requirement has a test, and every test names a live R-ID.
# Uses grep/sed/awk only, so it runs on macOS (BSD) and Linux (GNU). Do not call rg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQ="$ROOT/docs/requirements/dictation/02-requirements.md"
TEST_DIR="$ROOT/Tests"

if [[ ! -f "$REQ" ]]; then
  echo "error: requirements file not found: $REQ" >&2
  exit 1
fi

# Table rows: | R12 | requirement | src | test |
# Field 2 is the id, field 3 the requirement, field 5 the test column.
# Skip any row whose requirement cell contains REMOVED.
L_IDS="$(
  awk -F'|' '
    function has_word_l(cell,    n, i, parts, token) {
      n = split(cell, parts, /[^A-Za-z0-9_]+/)
      for (i = 1; i <= n; i++) {
        if (parts[i] == "L") return 1
      }
      return 0
    }
    {
      id = $2
      gsub(/[[:space:]]/, "", id)
      if (id !~ /^R[0-9]+$/) next
      if ($3 ~ /REMOVED/) next
      if (has_word_l($5)) print id
    }
  ' "$REQ"
)"

REMOVED_IDS="$(
  awk -F'|' '
    {
      id = $2
      gsub(/[[:space:]]/, "", id)
      if (id !~ /^R[0-9]+$/) next
      if ($3 ~ /REMOVED/) print id
    }
  ' "$REQ" | sort -u
)"

# func names only. grep -o -E --include is available on BSD and GNU grep.
TEST_NAMES="$(
  grep -R -h -o -E --include='*.swift' 'func[[:space:]]+test_[A-Za-z0-9_]+' "$TEST_DIR" \
    | sed -E 's/^func[[:space:]]+//' \
    | sort -u || true
)"

fail=0

echo "== L R-IDs missing a test =="
missing=0
while IFS= read -r rid; do
  [[ -z "$rid" ]] && continue
  # test_R2 must not match test_R20 or test_R21.
  if ! printf '%s\n' "$TEST_NAMES" | grep -E -q "^test_${rid}([^0-9]|$)"; then
    echo "  MISSING: $rid"
    missing=$((missing + 1))
    fail=1
  fi
done <<< "$L_IDS"
if [[ "$missing" -eq 0 ]]; then
  echo "  (none)"
fi

echo "== Tests whose names lack a live R-ID =="
bad=0
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  rid="$(printf '%s\n' "$name" | sed -n -E 's/^test_(R[0-9]+).*/\1/p')"
  if [[ -z "$rid" ]]; then
    echo "  BAD: $name"
    bad=$((bad + 1))
    fail=1
    continue
  fi
  if printf '%s\n' "$REMOVED_IDS" | grep -E -q "^${rid}$"; then
    echo "  REMOVED: $name ($rid)"
    bad=$((bad + 1))
    fail=1
  fi
done <<< "$TEST_NAMES"
if [[ "$bad" -eq 0 ]]; then
  echo "  (none)"
fi

echo "== Summary =="
l_count="$(printf '%s\n' "$L_IDS" | grep -c '^R' || true)"
t_count="$(printf '%s\n' "$TEST_NAMES" | grep -c '^test_R' || true)"
unique_count="$(
  printf '%s\n' "$TEST_NAMES" \
    | sed -n -E 's/^test_(R[0-9]+).*/\1/p' \
    | sort -u \
    | grep -c '^R' || true
)"
echo "  L requirements: $l_count"
echo "  tests with R-ID: $t_count"
echo "  unique R-IDs in tests: $unique_count"

if [[ "$fail" -ne 0 ]]; then
  echo "check-rids: FAILED" >&2
  exit 1
fi
echo "check-rids: OK"
