# Agent guide

## Repository and layout

- `origin`: https://github.com/edmund-munday/dictation.git; default branch: `main`.
  Work on feature branches and land changes through GitHub pull requests
  (`gh repo` / `gh pr`).
- `Package.swift` defines the Swift package. `Sources/DictationCore` contains
  platform-neutral logic; `Sources/DictationMac` contains macOS integrations;
  `Sources/DictationApp` contains the app. Tests mirror these under `Tests/`.
  Plugin examples live in `examples/plugins`; requirements are in `docs/requirements`.

## Setup, build and checks

Run commands from the repository root. Swift targets require Swift 6; the app
requires macOS 13+ and Apple's build/signing tools. Python plugin tests require
Python 3 (verified with 3.12) and a writable temporary directory; no pip packages
or package dependencies need installing.

Commands verified from a clean checkout in this Linux container, in order:

```sh
swift --version
python3 --version
scripts/test.sh
python3 -B -m unittest discover -s Tests/scripts -v
scripts/check-rids.sh
scripts/build-app.sh
```

- Swift is not installed here: the version check, both Swift invocations in
  `scripts/test.sh`, and the app build stop with `swift: not found`. No Swift
  tests execute. macOS integrations and the app also require macOS frameworks.
- The Python subset passes all 19 tests with writable temporary storage; it uses
  a fake Snip executable and needs no audio hardware or installed Snip.
- There is no dedicated formatter/linter. `scripts/check-rids.sh` checks requirement
  coverage/naming; it currently fails for missing R75 coverage and 55 test names
  without a live R-ID (G/M-prefixed names). It reports 90 L requirements, 360
  R-ID test names and 173 unique R-IDs.
- On macOS, `scripts/build-app.sh` builds `build/Dictation.app`.
  The official test command is `scripts/test.sh`: plain `swift test` skips
  `DictationMacTests`, so the script explicitly runs that group too. The opt-in
  `scripts/latency-bench.sh` needs real whisper and configured gateway access;
  see `docs/requirements/incremental-cleanup/02-requirements.md`.

## Rules

Follow [README.md](README.md) for gateway configuration: keep the gateway key out
of the repository, protect its configuration with mode 600, and never log
transcripts or cleanup results. Run targeted tests for changed behavior.
