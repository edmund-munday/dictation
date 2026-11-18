#!/bin/bash
# CI only: proves scripts/ensure-signing-identity.sh gives Dictation a stable signature.
# Creates the certificate in a throwaway keychain, builds the app twice, and checks both
# builds carry the same certificate-based designated requirement (what macOS permissions
# are tied to). Never run on a real Mac: it changes the keychain search list.
set -euo pipefail
KC="$RUNNER_TEMP/dictation-ci.keychain-db"
PW=ci
security create-keychain -p "$PW" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$PW" "$KC"
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')

export DICTATION_KEYCHAIN="$KC"
scripts/ensure-signing-identity.sh
# On a real Mac the first codesign shows a password dialog instead of this step.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null
scripts/ensure-signing-identity.sh | grep -q "already set up"

scripts/build-app.sh
codesign --verify --strict build/Dictation.app
first="$(codesign -d -r- build/Dictation.app 2>&1 | grep 'designated =')"
touch Sources/DictationApp/*.swift
scripts/build-app.sh
second="$(codesign -d -r- build/Dictation.app 2>&1 | grep 'designated =')"
echo "first:  $first"
echo "second: $second"
case "$first" in *"certificate leaf = H"*) ;; *) echo "FAIL: not signed with the certificate"; exit 1;; esac
[ "$first" = "$second" ] || { echo "FAIL: designated requirement changed between builds"; exit 1; }
echo "PASS: both builds share one certificate-based identity"
