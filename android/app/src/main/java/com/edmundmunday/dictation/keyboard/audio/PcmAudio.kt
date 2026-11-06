package com.edmundmunday.dictation.keyboard.audio

object PcmAudio {
    const val MODEL_RATE = 16_000

    fun toModelInput(pcm: ShortArray, sampleRate: Int): FloatArray {
        val samples = if (sampleRate == MODEL_RATE) pcm else resample(pcm, sampleRate, MODEL_RATE)
        return FloatArray(samples.size) { index -> samples[index] / 32768.0f }
    }

    fun littleEndianBytes(pcm: ShortArray): ByteArray {
        val out = ByteArray(pcm.size * 2)
        var at = 0
        for (sample in pcm) {
            val value = sample.toInt()
            out[at++] = (value and 0xff).toByte()
            out[at++] = (value shr 8 and 0xff).toByte()
        }
        return out
    }

    private fun resample(pcm: ShortArray, from: Int, to: Int): ShortArray {
        if (pcm.isEmpty() || from <= 0) return pcm
        val count = (pcm.size.toLong() * to / from).toInt()
        if (count <= 0) return ShortArray(0)
        val out = ShortArray(count)
        val ratio = from.toDouble() / to.toDouble()
        for (index in 0 until count) {
            val position = index * ratio
            val left = position.toInt()
            val fraction = (position - left).toFloat()
            val a = pcm[minOf(left, pcm.lastIndex)].toFloat()
            val b = pcm[minOf(left + 1, pcm.lastIndex)].toFloat()
            out[index] = (a + (b - a) * fraction).toInt().toShort()
        }
        return out
    }
}
