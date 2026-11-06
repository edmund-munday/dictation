package com.edmundmunday.dictation.keyboard.recogniser

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.edmundmunday.dictation.keyboard.audio.PcmAudio
import com.edmundmunday.dictation.keyboard.bench.PcmTranscriber
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Runs the on-device recogniser on a PCM buffer kept in memory.
 * The samples go through a pipe, never a file, so the bench can score the
 * same audio that whisper.cpp sees.
 */
class AndroidPcmTranscriber(private val context: Context) : PcmTranscriber {
    override val id: String = "android"

    override fun transcribe(pcm: ShortArray, sampleRate: Int): String {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            error("android transcription failed: must not run on the main thread")
        }
        val text = AtomicReference<String?>(null)
        val failure = AtomicReference<String?>(null)
        val done = CountDownLatch(1)
        Handler(Looper.getMainLooper()).post {
            try {
                listen(pcm, sampleRate, text, failure, done)
            } catch (error: Exception) {
                failure.set(error.message ?: "failed")
                done.countDown()
            }
        }
        if (!done.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            error("android transcription failed: timed out")
        }
        failure.get()?.let { error("android transcription failed: $it") }
        return text.get() ?: ""
    }

    private fun listen(
        pcm: ShortArray,
        sampleRate: Int,
        text: AtomicReference<String?>,
        failure: AtomicReference<String?>,
        done: CountDownLatch,
    ) {
        val request = androidRecognitionRequest(segmentedSessionAvailable = true)
        if (!request.onDeviceOnly) error("android transcription failed: network recogniser requested")
        val pipes = ParcelFileDescriptor.createPipe()
        val readSide = pipes[0]
        val writeSide = pipes[1]
        val listen = ContinuousListenController(segmentedSessionAvailable = true)
        listen.start()
        var finished = false
        var pipeClosed = false
        var sawResult = false
        var speech: SpeechRecognizer? = null
        fun finishOk() {
            if (finished) return
            finished = true
            listen.stop()
            text.set(listen.transcript)
            runCatching { speech?.destroy() }
            runCatching { readSide.close() }
            done.countDown()
        }
        fun finishError(message: String) {
            if (finished) return
            finished = true
            listen.cancel()
            failure.set(message)
            runCatching { speech?.destroy() }
            runCatching { readSide.close() }
            done.countDown()
        }
        fun finishIfReady() {
            if (pipeClosed && sawResult) finishOk()
        }
        val created = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        speech = created
        speech.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) = Unit
            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEvent(eventType: Int, params: Bundle?) = Unit
            override fun onPartialResults(partialResults: Bundle?) {
                listen.onPartial(recognitionText(partialResults) ?: return)
            }
            override fun onSegmentResults(segmentResults: Bundle) {
                listen.onSegment(recognitionText(segmentResults) ?: return)
                sawResult = true
            }
            override fun onResults(results: Bundle?) {
                listen.onSessionFinal(recognitionText(results) ?: "")
                sawResult = true
                finishIfReady()
            }
            override fun onEndOfSpeech() = Unit
            override fun onEndOfSegmentedSession() {
                finishOk()
            }
            override fun onError(error: Int) {
                if (listen.transcript.isNotBlank() && error == SpeechRecognizer.ERROR_NO_MATCH) {
                    finishOk()
                } else {
                    finishError("error $error")
                }
            }
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, request.language)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, request.partialResults)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readSide)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, sampleRate)
            putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
        }
        speech.startListening(intent)
        Thread {
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(writeSide).use { output ->
                    output.write(PcmAudio.littleEndianBytes(pcm))
                }
                Handler(Looper.getMainLooper()).post {
                    pipeClosed = true
                    finishIfReady()
                }
            } catch (error: Exception) {
                Handler(Looper.getMainLooper()).post { finishError("pipe write failed: ${error.message}") }
            }
        }.start()
    }

    companion object {
        private const val TIMEOUT_SECONDS = 60L
    }
}
