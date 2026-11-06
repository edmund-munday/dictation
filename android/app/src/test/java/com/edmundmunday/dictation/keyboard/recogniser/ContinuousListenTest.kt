package com.edmundmunday.dictation.keyboard.recogniser

import org.junit.Assert.assertEquals
import org.junit.Test

class ContinuousListenTest {
    @Test
    fun `restart mode joins segments without losing words`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = false)
        listen.start()
        listen.onSessionFinal("ship it friday")
        listen.onEndOfSpeech()
        listen.onSessionFinal("actually I mean monday")
        listen.onEndOfSpeech()
        listen.stop()
        assertEquals("ship it friday actually I mean monday", listen.transcript)
        assertEquals(2, listen.restartCount)
    }

    @Test
    fun `an overlapping join does not duplicate words`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = false)
        listen.start()
        listen.onSessionFinal("ship it friday")
        listen.onEndOfSpeech()
        listen.onSessionFinal("friday actually monday")
        listen.stop()
        assertEquals("ship it friday actually monday", listen.transcript)
    }

    @Test
    fun `a multi word overlap is joined once`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = false)
        listen.start()
        listen.onSessionFinal("I would also move the timeline")
        listen.onEndOfSpeech()
        listen.onSessionFinal("the timeline to the end")
        listen.stop()
        assertEquals("I would also move the timeline to the end", listen.transcript)
    }

    @Test
    fun `words that do not overlap are both kept`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = false)
        listen.start()
        listen.onSessionFinal("alpha")
        listen.onEndOfSpeech()
        listen.onSessionFinal("beta gamma")
        listen.stop()
        assertEquals("alpha beta gamma", listen.transcript)
    }

    @Test
    fun `overlap matching ignores case and keeps the earlier word`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = false)
        listen.start()
        listen.onSessionFinal("Hello there")
        listen.onEndOfSpeech()
        listen.onSessionFinal("There friend")
        listen.stop()
        assertEquals("Hello there friend", listen.transcript)
    }

    @Test
    fun `partials stay a tail until the final replaces them`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = false)
        listen.start()
        listen.onPartial("hello")
        listen.onPartial("hello world")
        assertEquals("hello world", listen.display)
        listen.onSessionFinal("hello world")
        listen.stop()
        assertEquals("hello world", listen.transcript)
    }

    @Test
    fun `a provisional partial is replaced by the later final without duplication`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = false)
        listen.start()
        listen.onPartial("hello wor")
        listen.stop()
        assertEquals("hello wor", listen.transcript)
        listen.onSessionFinal("hello world")
        assertEquals("hello world", listen.transcript)
    }

    @Test
    fun `silence restarts listening and keeps the words already heard`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = false)
        listen.start()
        listen.onSessionFinal("hello there")
        listen.onEndOfSpeech()
        listen.onSilence()
        listen.stop()
        assertEquals("hello there", listen.transcript)
        assertEquals(2, listen.restartCount)
    }

    @Test
    fun `segmented results do not restart and do not duplicate a repeated final`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = true)
        listen.start()
        listen.onPartial("ship it")
        listen.onSegment("ship it friday")
        listen.onPartial("actually")
        assertEquals("ship it friday actually", listen.display)
        listen.onSegment("actually I mean monday")
        listen.onSessionFinal("ship it friday actually I mean monday")
        listen.onEndOfSpeech()
        listen.stop()
        assertEquals(0, listen.restartCount)
        assertEquals("ship it friday actually I mean monday", listen.transcript)
    }

    @Test
    fun `a segmented session that ends early continues and joins the next one`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = true)
        listen.start()
        listen.onSegment("alpha beta")
        listen.onEndOfSegmentedSession()
        assertEquals(1, listen.restartCount)
        listen.onSegment("gamma")
        listen.stop()
        assertEquals("alpha beta gamma", listen.transcript)
    }

    @Test
    fun `classic callbacks still restart when a segmented session was requested`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = true)
        listen.start()
        listen.onSessionFinal("hello world")
        listen.onEndOfSpeech()
        assertEquals(1, listen.restartCount)
        listen.onSessionFinal("again")
        listen.stop()
        assertEquals("hello world again", listen.transcript)
    }

    @Test
    fun `after stop a late end of speech does not restart`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = false)
        listen.start()
        listen.onSessionFinal("hello")
        listen.stop()
        val restarts = listen.restartCount
        listen.onEndOfSpeech()
        listen.onSilence()
        listen.onEndOfSegmentedSession()
        assertEquals(restarts, listen.restartCount)
        assertEquals("hello", listen.transcript)
    }

    @Test
    fun `cancel drops the words and ignores a late final`() {
        val listen = ContinuousListenController(segmentedSessionAvailable = false)
        listen.start()
        listen.onPartial("hello world")
        listen.cancel()
        listen.onSessionFinal("hello world")
        listen.onEndOfSpeech()
        assertEquals("", listen.transcript)
        assertEquals(0, listen.restartCount)
    }
}
