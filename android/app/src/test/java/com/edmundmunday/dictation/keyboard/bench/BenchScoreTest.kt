package com.edmundmunday.dictation.keyboard.bench

import com.edmundmunday.dictation.keyboard.support.FakeClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BenchScoreTest {
    @Test
    fun `both recognisers transcribe the same in memory audio`() {
        val clock = FakeClock()
        val pcm = shortArrayOf(1, 2, 3, 4)
        val android = scripted("android", "the cat sat", costMs = 80, clock = clock)
        val whisper = scripted("whisper-small", "the dog sat", costMs = 400, clock = clock)
        val results = SameAudioBench(listOf(android, whisper)) { clock.now }
            .transcribe(pcm, 16_000)
        assertTrue(android.seen === pcm)
        assertTrue(whisper.seen === pcm)
        assertEquals(16_000, android.sampleRate)
        assertEquals(16_000, whisper.sampleRate)
        assertEquals(80L, results[0].stopToFinalMs)
        assertEquals(400L, results[1].stopToFinalMs)
    }

    @Test
    fun `a recogniser failure names the recogniser and is not scored as zero`() {
        val broken = object : PcmTranscriber {
            override val id = "whisper-base"
            override fun transcribe(pcm: ShortArray, sampleRate: Int): String {
                error("model missing")
            }
        }
        val error = runCatching {
            SameAudioBench(listOf(broken)) { 0L }.transcribe(shortArrayOf(1), 16_000)
        }.exceptionOrNull()
        assertTrue(error is IllegalStateException)
        assertTrue(error!!.message!!.contains("whisper-base"))
        assertTrue(error.message!!.contains("model missing"))
    }

    @Test
    fun `overall word error rate is the total errors over the total reference words`() {
        val first = scorePhrase(
            "a b",
            listOf(HypothesisResult("android", "a x", 10)),
        )
        val second = scorePhrase(
            "c d e f",
            listOf(HypothesisResult("android", "c d e f", 12)),
        )
        val overall = BenchReport(listOf(first, second)).overall("android")
        assertEquals(1, overall.errors)
        assertEquals(6, overall.referenceWords)
        assertEquals(1.0 / 6.0, overall.rate, 0.0001)
    }

    @Test
    fun `the exported json has per phrase scores and no audio`() {
        val phrase = scorePhrase(
            "the cat sat",
            listOf(HypothesisResult("android", "the dog sat", 80)),
        )
        val json = BenchReport(listOf(phrase)).toJson()
        assertTrue(json.contains("\"reference\":\"the cat sat\""))
        assertTrue(json.contains("\"hypothesis\":\"the dog sat\""))
        assertTrue(json.contains("\"substitutions\":1"))
        assertTrue(json.contains("\"deletions\":0"))
        assertTrue(json.contains("\"insertions\":0"))
        assertTrue(json.contains("\"referenceWords\":3"))
        assertTrue(json.contains("\"stopToFinalMs\":80"))
        assertTrue(json.contains("\"errors\":1"))
        assertFalse(json.contains("\"audio\""))
        assertFalse(json.contains("pcm"))
    }

    private fun scripted(
        id: String,
        text: String,
        costMs: Long,
        clock: FakeClock,
    ): RecordingTranscriber = RecordingTranscriber(id, text, costMs, clock)

    private class RecordingTranscriber(
        override val id: String,
        private val text: String,
        private val costMs: Long,
        private val clock: FakeClock,
    ) : PcmTranscriber {
        lateinit var seen: ShortArray
        var sampleRate: Int = 0
        override fun transcribe(pcm: ShortArray, sampleRate: Int): String {
            seen = pcm
            this.sampleRate = sampleRate
            clock.now += costMs
            return text
        }
    }
}
