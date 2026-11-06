package com.edmundmunday.dictation.keyboard.whisper

import com.edmundmunday.dictation.keyboard.audio.PcmAudio
import com.edmundmunday.dictation.keyboard.bench.PcmTranscriber
import java.io.File

class WhisperCppTranscriber(
    override val id: String,
    private val modelFile: File,
) : PcmTranscriber {
    private var context: Long = 0L

    override fun transcribe(pcm: ShortArray, sampleRate: Int): String {
        val ctx = context()
        val samples = PcmAudio.toModelInput(pcm, sampleRate)
        return try {
            WhisperJni.transcribe(ctx, samples).trim()
        } catch (error: Exception) {
            error("whisper transcription failed: ${modelFile.name}: ${error.message}")
        }
    }

    fun close() {
        val ctx = context
        context = 0L
        if (ctx != 0L) WhisperJni.freeContext(ctx)
    }

    private fun context(): Long {
        if (context != 0L) return context
        if (!modelFile.isFile) error("whisper model missing: ${modelFile.path}")
        val loaded = WhisperJni.initContext(modelFile.absolutePath)
        if (loaded == 0L) error("whisper model failed to load: ${modelFile.path}")
        context = loaded
        return loaded
    }
}
