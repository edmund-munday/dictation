#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef void (*IsPlaying)(dispatch_queue_t, void (^)(bool));
typedef bool (*SendCommand)(int, void *);

// Load into Apple-signed /usr/bin/perl: direct app calls are restricted on macOS 15.4+.
__attribute__((constructor))
static void mediactl(void) {
    const char *command = getenv("DICTATION_MEDIA_CMD");
    if (command == NULL) return;
    const bool status = strcmp(command, "status") == 0;
    int commandID = -1;
    if (strcmp(command, "play") == 0) commandID = 0;
    else if (strcmp(command, "pause") == 0) commandID = 1;
    else if (strcmp(command, "toggle") == 0) commandID = 2;
    else if (strcmp(command, "next") == 0) commandID = 4;
    else if (strcmp(command, "previous") == 0) commandID = 5;
    if (!status && commandID < 0) {
        puts("failed");
        fflush(stdout);
        return;
    }

    void *mediaRemote = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_LAZY);
    if (status) {
        IsPlaying isPlaying = mediaRemote == NULL ? NULL :
            (IsPlaying)dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        if (isPlaying == NULL) {
            puts("unknown");
        } else {
            __block bool playing = false;
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            isPlaying(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(bool value) {
                playing = value;
                dispatch_semaphore_signal(done);
            });
            long result = dispatch_semaphore_wait(done,
                dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC));
            puts(result == 0 ? (playing ? "playing" : "stopped") : "unknown");
            // Keep the framework and semaphore alive if a callback arrives after timeout.
        }
    } else {
        SendCommand sendCommand = mediaRemote == NULL ? NULL :
            (SendCommand)dlsym(mediaRemote, "MRMediaRemoteSendCommand");
        bool sent = sendCommand != NULL && sendCommand(commandID, NULL);
        // MediaRemote needs time to deliver the command before Perl exits.
        usleep(150000);
        puts(sent ? "ok" : "failed");
    }
    fflush(stdout);
}
