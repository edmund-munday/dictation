# Understanding / defaults chosen
- Gateway API (llm-gateway on the worker): `POST {url}/v1/chat`, header `Authorization: Bearer lgw_…`, JSON body
  `{"model","messages":[{role,content}],"max_output_tokens","timeout_ms","tool_tag"}`; success 200 `{"text": "..."}`;
  errors non-2xx `{"error":{"code","message"}}`. Not OpenAI-compatible. Only model offered: `deepseek/deepseek-flash`
  (thinking disabled server-side) — that is the default model; configurable.
- Config lives on the Mac at `~/Library/Application Support/Dictation/gateway.json` (chmod 600):
  `{"url":"http://100.87.52.73:8787","model":"deepseek/deepseek-flash","key":"lgw_…","timeoutSeconds":3}`.
  Key is never in the repo. Missing/invalid config or missing key -> gateway unavailable -> local rules.
- Deadline 3 s after release (session clock), then local rules; HTTP error / bad response -> local rules at once.
- CLIs stay available but are no longer probed at launch; they are reachable from the menu's re-choose action.
- Nothing logs the transcript or the cleaned text.
