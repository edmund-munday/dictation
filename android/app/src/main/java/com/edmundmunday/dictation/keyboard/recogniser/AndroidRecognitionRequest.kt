package com.edmundmunday.dictation.keyboard.recogniser

data class AndroidRecognitionRequest(
    val language: String,
    val partialResults: Boolean,
    val segmentedSession: Boolean,
    val onDeviceOnly: Boolean,
)

fun androidRecognitionRequest(segmentedSessionAvailable: Boolean): AndroidRecognitionRequest {
    return AndroidRecognitionRequest(
        language = "en-AU",
        partialResults = true,
        segmentedSession = segmentedSessionAvailable,
        onDeviceOnly = true,
    )
}
