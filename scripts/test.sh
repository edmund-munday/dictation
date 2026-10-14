#!/bin/sh
# Official test command (R208). Plain `swift test` does not run DictationMacTests on this
# package, so run them explicitly as well. Exits non-zero if either run fails.
set -u
cd "$(dirname "$0")/.."
status=0
echo "== swift test"
swift test "$@" || status=1
echo "== swift test --filter DictationMacTests"
swift test --filter DictationMacTests "$@" || status=1
exit $status
