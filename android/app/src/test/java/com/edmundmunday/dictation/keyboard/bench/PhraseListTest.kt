package com.edmundmunday.dictation.keyboard.bench

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class PhraseListTest {
    @Test
    fun `the bench file has twenty phrases including the dictionary words`() {
        val phrases = Phrases.load(Phrases.defaultFile())
        assertEquals(20, phrases.size)
        assertEquals(20, phrases.toSet().size)
        val text = phrases.joinToString("\n")
        assertTrue(text.contains("Kazey"))
        assertTrue(text.contains("Grok Bot"))
        assertTrue(text.contains("Grok Build"))
        assertTrue(text.contains("Snip"))
    }

    @Test
    fun `a missing phrase file fails and names the path`() {
        val missing = File("/tmp/dictation-phrases-missing.txt")
        val error = runCatching { Phrases.load(missing) }.exceptionOrNull()
        assertTrue(error is IllegalStateException)
        assertTrue(error!!.message!!.contains(missing.path))
    }

    @Test
    fun `the wrong number of phrases fails and names the file`() {
        val file = File.createTempFile("phrases", ".txt")
        file.writeText("only one\n")
        val error = runCatching { Phrases.load(file) }.exceptionOrNull()
        assertTrue(error is IllegalStateException)
        assertTrue(error!!.message!!.contains(file.path))
        assertTrue(error.message!!.contains("20"))
    }
}
