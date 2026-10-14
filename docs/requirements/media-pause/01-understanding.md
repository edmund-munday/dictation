# Understanding
- Verified on the Mac (macOS 26.6.2): a non-entitled binary calling MRMediaRemoteGetNowPlayingApplicationIsPlaying gets false while Music plays. The same call from a small dylib loaded into /usr/bin/perl (mediaremote-adapter approach) reports correctly in ~10-20 ms, and MRMediaRemoteSendCommand(pause=1 / play=0) from it pauses/resumes Music (needs ~150 ms before the process exits).
- So: explicit pause/play commands (never a toggle), detection via the perl-loaded dylib. Unknown state (helper missing, timeout, error) = do nothing.
- Media work runs on its own serial queue so recording start is never delayed; start and end stay ordered.
- Menu toggle "Pause media while dictating", UserDefaults key pauseMediaWhileDictating, default on.
