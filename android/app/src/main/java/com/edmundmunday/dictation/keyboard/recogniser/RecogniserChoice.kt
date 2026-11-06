package com.edmundmunday.dictation.keyboard.recogniser

import android.content.Context

enum class RecogniserChoice(val stored: String, val label: String) {
    ANDROID_ON_DEVICE("android", "Android on-device"),
    WHISPER_SMALL("whisper-small", "whisper.cpp small.en q5"),
    WHISPER_BASE("whisper-base", "whisper.cpp base.en q5"),
    ;

    companion object {
        fun parse(raw: String?): RecogniserChoice {
            if (raw.isNullOrEmpty()) return ANDROID_ON_DEVICE
            return entries.firstOrNull { it.stored == raw }
                ?: error("recogniser preference: unknown value '$raw'")
        }
    }
}

object RecogniserPrefs {
    private const val FILE = "dictation"
    private const val KEY = "recogniser"

    fun read(context: Context): RecogniserChoice {
        val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY)) return RecogniserChoice.ANDROID_ON_DEVICE
        return RecogniserChoice.parse(prefs.getString(KEY, null))
    }

    fun write(context: Context, choice: RecogniserChoice) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, choice.stored)
            .apply()
    }
}
