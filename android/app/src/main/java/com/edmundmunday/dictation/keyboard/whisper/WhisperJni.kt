package com.edmundmunday.dictation.keyboard.whisper

object WhisperJni {
    init {
        System.loadLibrary("dictation_whisper")
    }

    @JvmStatic
    external fun initContext(modelPath: String): Long

    @JvmStatic
    external fun freeContext(context: Long)

    @JvmStatic
    external fun transcribe(context: Long, samples: FloatArray): String
}
