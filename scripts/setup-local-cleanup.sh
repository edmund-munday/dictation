#!/usr/bin/env bash
# Sets up local clean-up: a llama.cpp model server on 127.0.0.1 that Dictation uses
# instead of the gateway, so nothing dictated leaves the Mac.
#
# Run on the Mac that should use the local model:
#   bash scripts/setup-local-cleanup.sh
#
# Safe to run again. It installs llama.cpp if missing, downloads the model if missing,
# (re)starts the model server as a LaunchAgent, writes gateway.json (backing up any
# existing one) and restarts Dictation if it is running.
#
# Overrides: MODEL_URL (a .gguf download URL), PORT (default 8080).
set -euo pipefail

MODEL_URL="${MODEL_URL:-https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q8_0.gguf}"
PORT="${PORT:-8080}"
SUPPORT="$HOME/Library/Application Support/Dictation"
MODEL_DIR="$SUPPORT/llm"
MODEL_PATH="$MODEL_DIR/$(basename "$MODEL_URL")"
GATEWAY="$SUPPORT/gateway.json"
LABEL="com.edmundmunday.dictation.llm"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="/tmp/dictation-llm.log"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'Error: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "this script is for macOS."
command -v brew >/dev/null || fail "Homebrew is not installed. Install it from https://brew.sh, then run this again."

step "llama.cpp"
if command -v llama-server >/dev/null; then
  echo "Already installed: $(command -v llama-server)"
else
  brew install llama.cpp
fi
SERVER="$(command -v llama-server)" || fail "llama-server not found after installing llama.cpp."

step "Model"
mkdir -p "$MODEL_DIR"
if [ -s "$MODEL_PATH" ]; then
  echo "Already downloaded: $MODEL_PATH"
else
  echo "Downloading $(basename "$MODEL_PATH") (a few GB) ..."
  curl -fL --retry 3 -o "$MODEL_PATH.part" "$MODEL_URL"
  mv "$MODEL_PATH.part" "$MODEL_PATH"
fi

step "Model server (LaunchAgent $LABEL)"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SERVER</string>
    <string>-m</string><string>$MODEL_PATH</string>
    <string>--host</string><string>127.0.0.1</string>
    <string>--port</string><string>$PORT</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST
plutil -lint "$PLIST" >/dev/null || fail "the LaunchAgent file is not valid: $PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Waiting for the model to load (up to 2 minutes) ..."
ok=""
for _ in $(seq 1 120); do
  if curl -fs "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"ok"'; then ok=1; break; fi
  sleep 1
done
[ -n "$ok" ] || fail "the model server did not come up on port $PORT. See $LOG."
echo "Model server is up on http://127.0.0.1:$PORT"

step "Dictation clean-up setting ($GATEWAY)"
if [ -f "$GATEWAY" ] && ! grep -q '"api": *"openai"' "$GATEWAY"; then
  backup="$GATEWAY.before-local-$(date +%Y%m%d-%H%M%S)"
  cp "$GATEWAY" "$backup"
  echo "Backed up the existing setting to: $backup"
fi
umask 077
cat > "$GATEWAY" <<JSON
{
  "url": "http://127.0.0.1:$PORT",
  "model": "local",
  "api": "openai",
  "timeoutSeconds": 3
}
JSON
chmod 600 "$GATEWAY"
echo "Clean-up now goes to the local model."

step "Dictation"
if pgrep -x Dictation >/dev/null; then
  osascript -e 'quit app "Dictation"' || true
  for _ in $(seq 1 10); do pgrep -x Dictation >/dev/null || break; sleep 1; done
fi
if [ -d /Applications/Dictation.app ]; then
  open /Applications/Dictation.app
  echo "Dictation restarted. Its menu should show: Cleanup: gateway (local)"
else
  echo "Dictation is not installed in /Applications yet. Install it (see README), then open it."
fi

printf '\nDone. To go back to the previous setting, copy the backup over gateway.json and reopen Dictation.\n'
