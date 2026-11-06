package com.edmundmunday.dictation.keyboard.audio

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Microphone capture held only in memory. Nothing here opens a file.
 */
class InMemoryPcm(private val sampleRate: Int = SAMPLE_RATE) {
    private val chunks = ArrayList<ShortArray>()
    private val running = AtomicBoolean(false)
    private var recorder: AudioRecord? = null
    private var reader: Thread? = null

    fun start() {
        if (running.get()) error("AudioRecord: already recording")
        val min = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (min <= 0) error("AudioRecord: microphone unavailable (buffer $min)")
        val record = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            min * 2,
        )
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            error("AudioRecord: microphone unavailable")
        }
        record.startRecording()
        if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            record.release()
            error("AudioRecord: microphone did not start")
        }
        recorder = record
        running.set(true)
        val thread = Thread {
            val buffer = ShortArray(min)
            while (running.get()) {
                val count = record.read(buffer, 0, buffer.size)
                if (count > 0) {
                    synchronized(chunks) { chunks.add(buffer.copyOf(count)) }
                }
            }
        }
        thread.name = "dictation-pcm"
        reader = thread
        thread.start()
    }

    fun stop(): ShortArray {
        running.set(false)
        val record = recorder
        recorder = null
        try {
            if (record != null && record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                record.stop()
            }
        } catch (failure: IllegalStateException) {
            error("AudioRecord: stop failed: ${failure.message}")
        } finally {
            record?.release()
        }
        reader?.join(1_000)
        reader = null
        return snapshot()
    }

    fun snapshot(): ShortArray {
        synchronized(chunks) {
            val size = chunks.sumOf { it.size }
            val out = ShortArray(size)
            var at = 0
            for (chunk in chunks) {
                chunk.copyInto(out, at)
                at += chunk.size
            }
            return out
        }
    }

    companion object {
        const val SAMPLE_RATE = 16_000
    }
}
