#!/bin/bash
# Volume plugin. Level comes from DICTATION_ARG_LEVEL; bare "mute"/"unmute" come from the transcript.
set -u
level="$(printf '%s' "${DICTATION_ARG_LEVEL:-}" | tr '[:upper:]' '[:lower:]' | tr -d '.,!?%')"
if [ -z "$level" ]; then
  t="$(cat | /usr/bin/python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("context",{}).get("transcript",""))
except Exception: print("")' | tr '[:upper:]' '[:lower:]')"
  case "$t" in *unmute*) level=unmute ;; *mute*) level=mute ;; esac
fi
level="${level#to }"; level="${level% percent}"
cur=$(osascript -e 'output volume of (get volume settings)')
words2num() {
  /usr/bin/python3 - "$1" <<'PY'
import sys,re
s=sys.argv[1].replace('-',' ')
u={'zero':0,'one':1,'two':2,'three':3,'four':4,'five':5,'six':6,'seven':7,'eight':8,'nine':9,'ten':10,'eleven':11,'twelve':12,'thirteen':13,'fourteen':14,'fifteen':15,'sixteen':16,'seventeen':17,'eighteen':18,'nineteen':19}
t={'twenty':20,'thirty':30,'forty':40,'fifty':50,'sixty':60,'seventy':70,'eighty':80,'ninety':90}
m=re.search(r'\d+',s)
if m: print(m.group()); sys.exit()
n=None
for w in s.split():
    if w in u: n=(n or 0)+u[w]
    elif w in t: n=(n or 0)+t[w]
    elif w=='hundred': n=(n or 1)*100
print('' if n is None else n)
PY
}
case "$level" in
  mute|off|silent) osascript -e 'set volume output muted true'; printf '{"notify":"Muted"}\n'; exit 0 ;;
  unmute|on) osascript -e 'set volume output muted false'; printf '{"notify":"Unmuted, volume %s"}\n' "$cur"; exit 0 ;;
  up|louder|higher) new=$((cur + 10)) ;;
  down|quieter|lower|softer) new=$((cur - 10)) ;;
  max|maximum|full) new=100 ;;
  half) new=50 ;;
  *) new="$(words2num "$level")"
     if [ -z "$new" ]; then echo "didn't understand volume '$level'" >&2; exit 1; fi ;;
esac
[ "$new" -gt 100 ] && new=100; [ "$new" -lt 0 ] && new=0
osascript -e "set volume output volume $new" -e 'set volume output muted false'
printf '{"notify":"Volume %s"}\n' "$new"
