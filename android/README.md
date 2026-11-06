# Dictation keyboard (phase 0)

Bare keyboard for the Pixel 8a. Talk starts and stops one take, and the raw final transcript is inserted with `commitText`. There is no cleanup and a take never uses the network. Whisper models are downloaded by setup into app-private storage and are not committed. Audio stays in memory.

Application id: `com.edmundmunday.dictation.keyboard`. minSdk 34, targetSdk 35, arm64-v8a.

## SDK

The Android SDK is not in git. JDK 17 or newer is required.

```
export ANDROID_HOME=$HOME/android-sdk
mkdir -p "$ANDROID_HOME"
# Unzip commandlinetools-linux-16111833_latest.zip so sdkmanager is at
# $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" --licenses
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" \
  "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;27.2.12479018" "cmake;3.22.1"
```

## Build

```
cd android
echo "sdk.dir=$ANDROID_HOME" > local.properties
./gradlew assembleDebug testDebugUnitTest
```

The first native build clones whisper.cpp v1.9.5 into `android/third_party/whisper.cpp` (gitignored) and compiles it for arm64-v8a.

## Install

```
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Open Dictation, enable the keyboard, grant the microphone, and download a model if you want whisper. Switch to this keyboard in a field, tap Talk, speak, tap Stop. The bench plays the 20 phrases in `bench/phrases.txt` one at a time, records each take in memory, and scores the Android on-device recogniser, whisper small.en q5 and whisper base.en q5 on that same buffer. Export writes JSON and opens the share sheet. No audio file is written.

## Phone check

- The keyboard asks for a segmented session (`EXTRA_SEGMENTED_SESSION` set to the 120 second minimum-length extra) so a pause does not end the take. If the engine ignores that and ends on silence, the take restarts and the words are joined.
- Whisper on the keyboard transcribes the whole in-memory take when you tap stop. The strip does not fill in word by word.
- The bench passes that same buffer to whisper and to the on-device recogniser through an in-memory pipe (`EXTRA_AUDIO_SOURCE`). If the recogniser refuses the pipe, that take is a named failure and is not scored as zero.
- The choice in spec section 2.2 is Edmund's after he sees the bench. This build records the word error rate and the stop-to-final time. It does not decide which recogniser is clearly better.
