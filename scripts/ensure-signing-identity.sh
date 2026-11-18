#!/bin/bash
# Makes sure this Mac has a self-signed code-signing certificate named
# "Dictation Local Code Signing". scripts/build-app.sh signs with it, so every rebuild
# keeps the same identity and macOS keeps the Accessibility, Input Monitoring and
# Microphone permissions across updates. Does nothing if the certificate already exists.
# The certificate never leaves this Mac and is used only to sign Dictation.
#
# The first build afterwards may show a macOS dialog asking whether codesign may use the
# key: enter your login password and choose Always Allow.
#
# Overrides (used by CI): DICTATION_KEYCHAIN (default: login keychain).
set -euo pipefail

NAME="Dictation Local Code Signing"
KEYCHAIN="${DICTATION_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
OPENSSL=/usr/bin/openssl   # macOS LibreSSL: its .p12 files import cleanly with `security`

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$NAME\""; then
  echo "Signing certificate already set up: $NAME"
  exit 0
fi

echo "Creating signing certificate: $NAME"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
pass="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -name "$NAME" -out "$tmp/id.p12" -passout "pass:$pass"
security import "$tmp/id.p12" -k "$KEYCHAIN" -f pkcs12 -P "$pass" -T /usr/bin/codesign >/dev/null
security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\"" \
  || { echo "Error: the certificate was imported but is not usable for code signing." >&2; exit 1; }
echo "Signing certificate created."
