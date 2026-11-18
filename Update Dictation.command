#!/bin/bash
# Double-click in Finder to update Dictation: gets the latest version, rebuilds the app,
# installs it in /Applications and reopens it.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$SELF")" || exit 1

finish() {
  echo
  if [ "$1" -eq 0 ]; then echo "Done. You can close this window."; else echo "Update failed (see above). You can close this window."; fi
  read -r -n 1 -s -p "Press any key to close."
  exit "$1"
}

if [ "${1:-}" != "--pulled" ]; then
  echo "==> Getting the latest version"
  git checkout -q main && git pull --ff-only || finish 1
  exec "$SELF" --pulled   # run the copy just pulled, in case this file changed
fi

echo "==> Signing certificate (keeps permissions across updates)"
scripts/ensure-signing-identity.sh || finish 1

echo "==> Building Dictation (a few minutes)"
scripts/build-app.sh || finish 1

echo "==> Installing"
osascript -e 'quit app "Dictation"' >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Dictation >/dev/null || break; sleep 1; done
rm -rf /Applications/Dictation.app && cp -R build/Dictation.app /Applications/ || finish 1
open /Applications/Dictation.app || finish 1
echo "Dictation is updated and running."
finish 0
