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

Run commands from the repository root. Swift tests and the app require Swift 6
and macOS 13+. Building the app also requires Apple's build/signing tools.
Python plugin tests run anywhere with Python 3 and a writable temporary directory;
no pip packages or package dependencies need installing.

Available commands:

```sh
swift --version
python3 --version
scripts/test.sh
python3 -B -m unittest discover -s Tests/scripts -v
scripts/check-rids.sh
scripts/build-app.sh
```

- Python plugin tests use a fake Snip executable and need no audio hardware or
  installed Snip.
- There is no dedicated formatter/linter. `scripts/check-rids.sh` checks that every
  non-removed requirement marked `L` has a Swift test named for its R-ID, and flags
  test names that lack an R-ID or refer to a removed requirement. It also
  summarizes requirement and test IDs.
- On macOS, `scripts/build-app.sh` builds `build/Dictation.app`.
  The official test command is `scripts/test.sh`: plain `swift test` skips
  `DictationMacTests`, so the script explicitly runs that group too. The opt-in
  `scripts/latency-bench.sh` needs real whisper and configured gateway access;
  see `docs/requirements/incremental-cleanup/02-requirements.md`.

## Rules

Follow [README.md](README.md) for gateway configuration: keep the gateway key out
of the repository, protect its configuration with mode 600, and never log
transcripts or cleanup results. Run targeted tests for changed behavior.
