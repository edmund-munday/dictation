#!/bin/bash
# Media plugin: explicit MediaRemote commands via Apple-signed perl + Dictation's mediactl.dylib.
# DICTATION_MEDIA_WAS_PLAYING=1 means the dictation itself paused playback (handed off to us, not resumed).
set -u
t="$(cat | /usr/bin/python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("context",{}).get("transcript",""))
except Exception: print("")' | tr '[:upper:]' '[:lower:]' | tr -d '.,!?')"
lib="${DICTATION_APP_RESOURCES:-}/mediactl.dylib"
[ -f "$lib" ] || lib="$HOME/dictation-think/integrate/build/Dictation.app/Contents/Resources/mediactl.dylib"
[ -f "$lib" ] || { echo "mediactl helper not found" >&2; exit 1; }
mc() { DICTATION_MEDIA_CMD="$1" /usr/bin/perl -e 'require DynaLoader; DynaLoader::dl_load_file($ARGV[0],0) or exit 3' "$lib"; }
was="${DICTATION_MEDIA_WAS_PLAYING:-0}"
case "$t" in
  *"play pause"*) mc toggle >/dev/null; note="Play/pause" ;;
  *next*|*skip*) mc next >/dev/null; [ "$was" = 1 ] && mc play >/dev/null; note="Next track" ;;
  *previous*|*last*) mc previous >/dev/null; [ "$was" = 1 ] && mc play >/dev/null; note="Previous track" ;;
  *pause*|*stop*) mc pause >/dev/null; note="Paused" ;;
  *play*|*resume*) mc play >/dev/null; note="Playing" ;;
  *) echo "unknown media command: $t" >&2; exit 1 ;;
esac
printf '{"notify":"%s"}\n' "$note"
