#include <jni.h>
#include <string>
#include "whisper.h"

namespace {

std::string join_segments(whisper_context * ctx) {
    std::string out;
    const int count = whisper_full_n_segments(ctx);
    for (int index = 0; index < count; index++) {
        const char * text = whisper_full_get_segment_text(ctx, index);
        if (text == nullptr) continue;
        std::string piece(text);
        const auto first = piece.find_first_not_of(" \t\r\n");
        if (first == std::string::npos) continue;
        const auto last = piece.find_last_not_of(" \t\r\n");
        piece = piece.substr(first, last - first + 1);
        if (piece.empty() || piece.front() == '[' || piece.front() == '(') continue;
        if (!out.empty()) out.push_back(' ');
        out += piece;
    }
    return out;
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_edmundmunday_dictation_keyboard_whisper_WhisperJni_initContext(
        JNIEnv * env, jclass, jstring path) {
    const char * model = env->GetStringUTFChars(path, nullptr);
    if (model == nullptr) return 0;
    whisper_context_params params = whisper_context_default_params();
    params.use_gpu = false;
    whisper_context * ctx = whisper_init_from_file_with_params(model, params);
    env->ReleaseStringUTFChars(path, model);
    return reinterpret_cast<jlong>(ctx);
}

extern "C" JNIEXPORT void JNICALL
Java_com_edmundmunday_dictation_keyboard_whisper_WhisperJni_freeContext(
        JNIEnv *, jclass, jlong context) {
    if (context == 0) return;
    whisper_free(reinterpret_cast<whisper_context *>(context));
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_edmundmunday_dictation_keyboard_whisper_WhisperJni_transcribe(
        JNIEnv * env, jclass, jlong context, jfloatArray samples) {
    if (context == 0 || samples == nullptr) {
        return env->NewStringUTF("");
    }
    whisper_context * ctx = reinterpret_cast<whisper_context *>(context);
    const jsize count = env->GetArrayLength(samples);
    jfloat * pcm = env->GetFloatArrayElements(samples, nullptr);
    if (pcm == nullptr) return env->NewStringUTF("");

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = 4;
    params.translate = false;
    params.language = "en";
    params.detect_language = false;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.print_special = false;
    params.no_timestamps = true;
    params.single_segment = false;
    params.suppress_blank = true;
    params.suppress_nst = true;

    const int failed = whisper_full(ctx, params, pcm, count);
    env->ReleaseFloatArrayElements(samples, pcm, JNI_ABORT);
    if (failed != 0) {
        jclass type = env->FindClass("java/lang/IllegalStateException");
        env->ThrowNew(type, "whisper.cpp: whisper_full failed");
        return nullptr;
    }
    const std::string text = join_segments(ctx);
    return env->NewStringUTF(text.c_str());
}
