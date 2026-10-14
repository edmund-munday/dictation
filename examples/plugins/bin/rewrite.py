#!/usr/bin/python3
"""Rewrite-selection plugin: selection + instruction -> LLM gateway -> {"replace": ...}.
Gateway URL/model/key come from ../../gateway.json; the key is never printed."""
import json, os, sys, urllib.request

def out(obj):
    print(json.dumps(obj, ensure_ascii=False)); sys.exit(0)

try:
    payload = json.load(sys.stdin)
except Exception:
    payload = {}
ctx = payload.get("context", {}) or {}
selection = os.environ.get("DICTATION_SELECTED_TEXT") or ctx.get("selected_text") or ""
instruction = (os.environ.get("DICTATION_ARG_INSTRUCTION") or (payload.get("args") or {}).get("instruction") or "").strip()
if not selection.strip():
    out({"notify": "Select some text first."})
if not instruction:
    out({"notify": "Say how to rewrite it, e.g. 'make this shorter'."})

cfg_path = os.path.expanduser("~/Library/Application Support/Dictation/gateway.json")
try:
    cfg = json.load(open(cfg_path))
except Exception:
    print("gateway.json missing or unreadable", file=sys.stderr); sys.exit(1)

system = (
    "You rewrite a piece of text written by Edmund according to his spoken instruction.\n"
    "Follow the instruction faithfully (e.g. 'shorter' means noticeably shorter; 'bullets' means a bulleted list "
    "using '- ' lines; 'more formal' changes register only).\n"
    "Preserve Edmund's voice, meaning, facts, names, numbers and language. Do not add new content, opinions, "
    "greetings or sign-offs he did not write. Keep the same perspective (I/we/you).\n"
    "Output ONLY the rewritten text: no preamble, no explanation, no quotes or code fences around it."
)
user = f"Instruction: {instruction}\n\nText to rewrite:\n<<<\n{selection}\n>>>"
body = {
    "model": "deepseek/deepseek-flash",
    "temperature": 0.2,
    "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
    "max_output_tokens": max(400, min(4000, len(selection) // 2 + 400)),
    "timeout_ms": 25000,
    "tool_tag": "dictation:rewrite",
}
req = urllib.request.Request(cfg["url"].rstrip("/") + "/v1/chat", data=json.dumps(body).encode(),
                             headers={"Authorization": "Bearer " + cfg["key"], "Content-Type": "application/json"},
                             method="POST")
try:
    with urllib.request.urlopen(req, timeout=27) as r:
        text = (json.load(r).get("text") or "").strip()
except Exception as e:
    print(f"gateway error: {type(e).__name__}", file=sys.stderr); sys.exit(1)
if text.startswith("```"):
    text = text.strip("`").split("\n", 1)[-1].rstrip("`").strip()
if not text:
    print("gateway returned no text", file=sys.stderr); sys.exit(1)
out({"replace": text, "notify": "Rewritten"})
