#!/bin/bash
# Double-click in Finder to make Dictation clean up text with a model on this Mac
# instead of the gateway. Safe to run again.
cd "$(dirname "$0")" || exit 1
bash scripts/setup-local-cleanup.sh
status=$?
echo
read -r -n 1 -s -p "Press any key to close."
exit $status
