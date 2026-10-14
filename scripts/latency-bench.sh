#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
DICTATION_LATENCY_BENCH=1 swift test --filter LatencyBenchTests
