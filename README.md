# dictation

Voice dictation for macOS. Hold left Command, talk, let go: the text appears in whatever
field has focus. Speech recognition always runs on the Mac (whisper.cpp). The clean-up
step (fillers, self-corrections such as "actually I mean", punctuation) runs one of two ways:

- **Gateway** (personal laptop): an external LLM through the LLM gateway.
- **Local** (work laptop): a model running on the Mac through llama.cpp, so no dictated
  text leaves the machine.

One file, `~/Library/Application Support/Dictation/gateway.json`, picks between them.
Everything else is identical on both machines.

## Set up on a new Mac

You need an Apple Silicon Mac on macOS 13 or later, Homebrew, and GitHub access to this
repository. The steps below are for a fresh machine; on the work laptop do all of them,
then follow "Clean-up option B".

### 1. Install the tools

```sh
xcode-select --install          # Swift compiler and git (skip if already installed)
brew install whisper-cpp        # speech recognition (provides whisper-cli)
```

Check that `swift --version` reports Swift 6 or later. If it reports Swift 5, update the
Command Line Tools (Software Update) or install Xcode.

### 2. Download the speech model

```sh
mkdir -p "$HOME/Library/Application Support/Dictation/models"
curl -L -o "$HOME/Library/Application Support/Dictation/models/ggml-small.en-q5_1.bin" \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin
```

The app uses `ggml-small.en-q5_1.bin` when present, otherwise `ggml-base.en.bin` from the
same folder. If neither the model nor `whisper-cli` is found, it falls back to Apple's
on-device speech recognition.

### 3. Clone and build the app

```sh
git clone https://github.com/edmund-munday/dictation.git ~/dictation
cd ~/dictation
scripts/build-app.sh
rm -rf /Applications/Dictation.app && cp -R build/Dictation.app /Applications/
open /Applications/Dictation.app
```

The app lives in the menu bar (no Dock icon).

### 4. Grant permissions

On first launch, open the menu-bar icon. It lists any missing permissions with a button
that opens the right System Settings pane. Allow Dictation under Privacy & Security:

- **Microphone**
- **Accessibility** (to type into the focused field)
- **Input Monitoring** (to see the left Command key; the talk key is inactive until this is allowed)

Then click **Refresh permissions** in the menu. If a permission still shows as missing,
quit and reopen the app.

The build is signed ad hoc, so macOS treats each rebuild as a new app: after rebuilding,
remove Dictation from those three lists and allow it again. To avoid that, create a
code-signing certificate named `Dictation Local Code Signing` in Keychain Access
(Certificate Assistant, type Code Signing); `scripts/build-app.sh` uses it automatically.

### 5. Start at login (optional)

System Settings, General, Login Items, then add `/Applications/Dictation.app`.

## Clean-up option A: gateway (personal laptop)

Create `~/Library/Application Support/Dictation/gateway.json`:

```json
{
  "url": "https://your-gateway-host",
  "model": "deepseek/deepseek-flash",
  "key": "your-gateway-key",
  "timeoutSeconds": 3
}
```

Protect it with `chmod 600 "$HOME/Library/Application Support/Dictation/gateway.json"` and
keep the key out of the repository. Cleanup POSTs to `<url>/v1/chat`. `model` and
`timeoutSeconds` are optional (defaults `deepseek/deepseek-flash` and 5 seconds).

## Clean-up option B: local model (work laptop)

Nothing dictated leaves the Mac: speech recognition is local and clean-up goes to a
llama.cpp server on `127.0.0.1`.

1. Install llama.cpp and download a model (about 3.3 GB):

   ```sh
   brew install llama.cpp
   mkdir -p "$HOME/Library/Application Support/Dictation/llm"
   curl -L -o "$HOME/Library/Application Support/Dictation/llm/qwen2.5-3b-instruct-q8_0.gguf" \
     https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q8_0.gguf
   ```

2. Keep the model server running, including after restarts, with a LaunchAgent:

   ```sh
   cat > ~/Library/LaunchAgents/com.edmundmunday.dictation.llm.plist <<PLIST
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>Label</key><string>com.edmundmunday.dictation.llm</string>
     <key>ProgramArguments</key>
     <array>
       <string>$(brew --prefix)/bin/llama-server</string>
       <string>-m</string><string>$HOME/Library/Application Support/Dictation/llm/qwen2.5-3b-instruct-q8_0.gguf</string>
       <string>--host</string><string>127.0.0.1</string>
       <string>--port</string><string>8080</string>
     </array>
     <key>RunAtLoad</key><true/>
     <key>KeepAlive</key><true/>
     <key>StandardErrorPath</key><string>/tmp/dictation-llm.log</string>
   </dict>
   </plist>
   PLIST
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.edmundmunday.dictation.llm.plist
   ```

   Check it is up (give it a few seconds to load the model): `curl -s http://127.0.0.1:8080/health`
   should print `{"status":"ok"}`.

3. Point the app at it. Create `~/Library/Application Support/Dictation/gateway.json`:

   ```json
   {
     "url": "http://127.0.0.1:8080",
     "model": "local",
     "api": "openai",
     "timeoutSeconds": 3
   }
   ```

   `"api": "openai"` sends clean-up to `<url>/v1/chat/completions`, the standard format
   llama.cpp and Ollama serve, and needs no key. Without `api`, the file means the gateway
   (option A).

4. Quit and reopen Dictation. The menu shows `Cleanup: gateway (local)`, which here means
   the local server.

If the server is down or slower than `timeoutSeconds`, clean-up falls back to the built-in
rules for that phrase, and nothing is sent anywhere. To try a different model, change the
`.gguf` path in the plist, then run
`launchctl kickstart -k gui/$(id -u)/com.edmundmunday.dictation.llm`.

Without any `gateway.json`, the app uses the built-in rules only. The grok, Claude and
Cursor CLIs are also available from the menu; they send text to those services, so do
not pick them on the work laptop.

## Using it

- **Hold left Command** and talk; release to insert. Pressing any other key while holding
  cancels, so normal Command shortcuts still work.
- **Ctrl-Opt-Space** pauses or resumes dictation.
- Say "comma", "full stop", "question mark", "new line" or "new paragraph" for punctuation.
- "Ship it Friday, actually I mean Monday" inserts "Ship it Monday."
- In chat apps (Slack, Messages, WhatsApp and others) the message is sent after inserting;
  end with "don't send" to stop that, or turn off **Auto-send in chat apps** in the menu.
- Extra words for the recogniser (names, jargon) go one per line in
  `~/Library/Application Support/Dictation/dictionary.txt`.
- **Save dictations for tuning** (on by default) keeps a local log of transcripts in
  `~/Library/Application Support/Dictation/corpus`; it is never uploaded. Turn it off in
  the menu if you do not want it on disk.

## Updating

```sh
cd ~/dictation && git pull && scripts/build-app.sh
osascript -e 'quit app "Dictation"'
rm -rf /Applications/Dictation.app && cp -R build/Dictation.app /Applications/
open /Applications/Dictation.app
```

Re-grant the permissions afterwards unless you set up the signing certificate (step 4).

## Troubleshooting

- **Nothing happens when holding Command:** Input Monitoring is missing, or the app was
  rebuilt; re-allow it and click Refresh permissions.
- **Text appears in the panel but not the field:** Accessibility is missing; the panel
  offers a Copy button meanwhile.
- **Clean-up looks like plain rules (no self-corrections fixed):** check
  `curl -s http://127.0.0.1:8080/health`, and `/tmp/dictation-llm.log`. The first phrase
  after a restart can time out while the model loads.

## Development

The official test command on macOS is `scripts/test.sh`. It runs both `swift test` and
`swift test --filter DictationMacTests`; plain `swift test` skips `DictationMacTests`.
On Linux only `DictationCore` and its tests are built, so `swift test` runs the core suite.

## Brief (Edmund's words, verbatim)

> macOS tool that effectively replaces the keyboard with voice dictation in any text input field (mouse/keyboard still available). Entirely automated start: always listening, with an on/off toggle, built assuming it is ON far more than just when typing, so it must cope with speech not meant for a text field. Low latency is a big consideration. Cleanup: fix what he says including self-corrections like 'actually, I mean xyz', producing exactly what he intended without changing meaning. Runs on his MacBook first, work laptop later, so fully local: self-hosted models, or Cursor CLI / Claude CLI as backing tool; no cloud. English assumed (unconfirmed).

See `docs/requirements.md`.
