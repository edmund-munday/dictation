package com.edmundmunday.dictation.keyboard.recogniser

import android.os.Bundle
import android.speech.SpeechRecognizer

fun recognitionText(bundle: Bundle?): String? {
    val list = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: return null
    return list.firstOrNull()
}
