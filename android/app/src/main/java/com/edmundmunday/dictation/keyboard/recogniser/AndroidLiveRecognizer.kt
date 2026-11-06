package com.edmundmunday.dictation.keyboard.recogniser

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.edmundmunday.dictation.keyboard.session.KeyboardSession

/**
 * On-device recogniser for the keyboard. Segmented sessions are requested
 * when available; otherwise the controller restarts the session after a pause
 * and joins the words.
 */
class AndroidLiveRecognizer(
    private val context: Context,
    private val session: KeyboardSession,
    private val segmentedSessionAvailable: Boolean,
    private val onFailure: (String) -> Unit,
    private val onDisplay: () -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var recogniser: SpeechRecognizer? = null
    private var running = false
    private var appliedRestarts = 0

    fun start() {
        running = true
        appliedRestarts = session.restartCount
        openSession()
    }

    fun stop() {
        running = false
        recogniser?.stopListening()
    }

    fun cancel() {
        running = false
        val current = recogniser
        recogniser = null
        current?.cancel()
        current?.destroy()
    }

    private fun openSession() {
        recogniser?.destroy()
        val speech = try {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        } catch (error: Exception) {
            running = false
            onFailure("on-device recogniser failed: ${error.message}")
            return
        }
        recogniser = speech
        speech.setRecognitionListener(listener)
        speech.startListening(liveIntent(context, segmentedSessionAvailable))
    }

    private fun syncRestart() {
        val count = session.restartCount
        if (!running || count <= appliedRestarts) return
        appliedRestarts = count
        handler.post {
            if (running) openSession()
        }
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit

        override fun onPartialResults(partialResults: Bundle?) {
            session.onPartial(recognitionText(partialResults) ?: return)
            onDisplay()
            syncRestart()
        }

        override fun onResults(results: Bundle?) {
            session.onSessionFinal(recognitionText(results) ?: "")
            onDisplay()
            syncRestart()
        }

        override fun onSegmentResults(segmentResults: Bundle) {
            session.onSegment(recognitionText(segmentResults) ?: return)
            onDisplay()
            syncRestart()
        }

        override fun onEndOfSpeech() {
            session.onEndOfSpeech()
            syncRestart()
        }

        override fun onEndOfSegmentedSession() {
            session.onEndOfSegmentedSession()
            syncRestart()
        }

        override fun onError(error: Int) {
            if (!running) return
            if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
                running = false
                onFailure("Microphone permission is off: open setup.")
                return
            }
            if (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                session.onSilence()
                syncRestart()
                return
            }
            running = false
            onFailure("on-device recogniser failed: error $error")
        }
    }

    companion object {
        fun liveIntent(context: Context, segmentedSessionAvailable: Boolean): Intent {
            val request = androidRecognitionRequest(segmentedSessionAvailable)
            return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, request.language)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, request.partialResults)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
                if (!request.onDeviceOnly) error("recogniser request left the on-device path")
                if (request.segmentedSession) {
                    putExtra(
                        RecognizerIntent.EXTRA_SEGMENTED_SESSION,
                        RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                    )
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 120_000)
                }
            }
        }
    }
}
