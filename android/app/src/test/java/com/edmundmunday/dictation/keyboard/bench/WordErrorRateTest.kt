package com.edmundmunday.dictation.keyboard.bench

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WordErrorRateTest {
    @Test
    fun `an exact transcript has zero errors`() {
        val score = wordErrorRate("Hey Kazey, thanks.", "hey kazey thanks")
        assertEquals(0, score.errors)
        assertEquals(0, score.substitutions)
        assertEquals(0, score.deletions)
        assertEquals(0, score.insertions)
        assertEquals(3, score.referenceWords)
        assertEquals(0.0, score.rate, 0.0001)
    }

    @Test
    fun `one substituted word is one error`() {
        val score = wordErrorRate("the cat sat", "the dog sat")
        assertEquals(1, score.substitutions)
        assertEquals(0, score.deletions)
        assertEquals(0, score.insertions)
        assertEquals(3, score.referenceWords)
        assertEquals(1.0 / 3.0, score.rate, 0.0001)
    }

    @Test
    fun `a missing word is a deletion`() {
        val score = wordErrorRate("the cat sat", "the sat")
        assertEquals(0, score.substitutions)
        assertEquals(1, score.deletions)
        assertEquals(0, score.insertions)
    }

    @Test
    fun `an extra word is an insertion`() {
        val score = wordErrorRate("the cat", "the big cat")
        assertEquals(0, score.substitutions)
        assertEquals(0, score.deletions)
        assertEquals(1, score.insertions)
        assertEquals(2, score.referenceWords)
        assertEquals(0.5, score.rate, 0.0001)
    }

    @Test
    fun `an empty hypothesis deletes every reference word`() {
        val score = wordErrorRate("Grok Bot files the note", "")
        assertEquals(5, score.deletions)
        assertEquals(5, score.referenceWords)
        assertEquals(1.0, score.rate, 0.0001)
    }

    @Test
    fun `a reference with no words is a failed score`() {
        val error = runCatching { wordErrorRate("...", "hello") }.exceptionOrNull()
        assertTrue(error is IllegalStateException)
        assertTrue(error!!.message!!.contains("word error rate"))
    }
}
