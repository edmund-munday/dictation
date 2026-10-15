# Understanding (data, 15 Oct 2026)

Gateway ledger on the PC (read-only), tool "dictation", 1676 charged calls 14 Oct 12:57 PM - 15 Oct 4:38 PM
Melbourne: latency p50 ~1.06 s, p90 ~1.49 s, p99 ~1.8 s. Latency does not grow with input size (input tokens
0-400: p99 1706 ms; 400-600: p99 1945; 1500-2000: p99 1627; 2000+: p99 4714, n=74). Calls over 3 s: 5 of 1676
(0.3%): 3526, 4956, 9035, 4869, 4714 ms; over 5 s: 1 (9035 ms). So length scaling is not justified; a flat 5 s
timeout keeps 4 of the 5 outliers.

Outage: 15 Oct 12:18 PM - 3:46 PM DeepSeek returned 503 "Service is too busy", then every call
(171/171) timed out upstream (even with 30 s). In the corpus 96 of 99 dictations in that window fell back to
local rules at ~3.0 s. Recovered 3:53 PM (58 calls since, p99 1.8 s).

Mislabel: the corpus field `backend` is "gateway" only when the gateway's text differs from what local rules
would produce (Session.recordUtterance). When the gateway returns the same text (common for clean short
sentences) it is logged "local", e.g. 24 of 31 dictations after recovery are "local" with ~0.6-1 s latency
although the gateway answered. Outside the outage, real fallbacks were ~3 timeouts on 14 Oct. The corpus has no
record of why a fallback happened.

Background per-sentence calls: at most 2 in flight; the release call does not use those slots. With ~1 s
calls and sentences every 3-5 s of speech, no starvation; during an outage each slot is freed at the timeout.

Change: default timeout 5 s (GatewayConfig default and the Mac's gateway.json), and record the real cleanup
outcome per utterance so the fallback rate and cause can be read from the corpus.
