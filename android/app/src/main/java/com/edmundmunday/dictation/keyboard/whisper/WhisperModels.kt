package com.edmundmunday.dictation.keyboard.whisper

import java.io.File

enum class WhisperModel {
    SMALL,
    BASE,
}

object WhisperModels {
    private const val SMALL_FILE = "ggml-small.en-q5_1.bin"
    private const val BASE_FILE = "ggml-base.en-q5_1.bin"
    private const val HOST = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"

    fun fileName(model: WhisperModel): String {
        return when (model) {
            WhisperModel.SMALL -> SMALL_FILE
            WhisperModel.BASE -> BASE_FILE
        }
    }

    fun url(model: WhisperModel): String = HOST + fileName(model)

    fun file(filesDir: File, model: WhisperModel): File {
        return File(File(filesDir, "models"), fileName(model))
    }
}
