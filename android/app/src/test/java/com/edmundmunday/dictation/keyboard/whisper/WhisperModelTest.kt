package com.edmundmunday.dictation.keyboard.whisper

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class WhisperModelTest {
    @Test
    fun `small and base models are q5 english files under app private storage`() {
        val filesDir = File("/tmp/dictation-files")
        val small = WhisperModels.file(filesDir, WhisperModel.SMALL)
        val base = WhisperModels.file(filesDir, WhisperModel.BASE)
        assertEquals("ggml-small.en-q5_1.bin", small.name)
        assertEquals("ggml-base.en-q5_1.bin", base.name)
        assertEquals("models", small.parentFile!!.name)
        assertEquals(small.parentFile, base.parentFile)
        assertTrue(small.path.startsWith(filesDir.path))
        assertTrue(WhisperModels.url(WhisperModel.SMALL).contains("ggml-small.en-q5_1.bin"))
        assertTrue(WhisperModels.url(WhisperModel.BASE).contains("ggml-base.en-q5_1.bin"))
    }
}
