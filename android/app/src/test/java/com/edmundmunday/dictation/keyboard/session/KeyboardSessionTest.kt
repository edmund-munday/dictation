package com.edmundmunday.dictation.keyboard.session

import com.edmundmunday.dictation.keyboard.recogniser.ContinuousListenController
import com.edmundmunday.dictation.keyboard.support.FakeClock
import com.edmundmunday.dictation.keyboard.take.TakeState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardSessionTest {
    @Test
    fun `the final after the stop tap is inserted once and left raw`() {
        val clock = FakeClock()
        val inserted = mutableListOf<String>()
        val session = session(clock, inserted)
        session.tapTalk()
        clock.now = 350
        session.tapTalk()
        assertTrue(inserted.isEmpty())
        session.onSessionFinal("um hello Kazey")
        assertEquals(listOf("um hello Kazey"), inserted)
        session.onSessionFinal("late extra")
        assertEquals(listOf("um hello Kazey"), inserted)
    }

    @Test
    fun `a take under 300 ms inserts nothing`() {
        val clock = FakeClock()
        val inserted = mutableListOf<String>()
        val session = session(clock, inserted)
        session.tapTalk()
        clock.now = 299
        session.tapTalk()
        session.onSessionFinal("hello")
        assertTrue(inserted.isEmpty())
        assertEquals(TakeState.READY, session.state)
    }

    @Test
    fun `cancel while processing inserts nothing`() {
        val clock = FakeClock()
        val inserted = mutableListOf<String>()
        val session = session(clock, inserted)
        session.tapTalk()
        clock.now = 800
        session.tapTalk()
        session.cancel()
        session.onSessionFinal("hello")
        assertTrue(inserted.isEmpty())
        assertEquals(TakeState.READY, session.state)
    }

    @Test
    fun `the 120 second cap inserts the final transcript and shows the cap message`() {
        val clock = FakeClock()
        val inserted = mutableListOf<String>()
        val session = session(clock, inserted)
        session.tapTalk()
        session.onPartial("hello there")
        clock.now = 120_000
        session.onTime()
        assertEquals("Maximum length reached.", session.strip)
        assertEquals(TakeState.PROCESSING, session.state)
        session.onSessionFinal("hello there friend")
        assertEquals(listOf("hello there friend"), inserted)
    }

    private fun session(clock: FakeClock, inserted: MutableList<String>): KeyboardSession {
        return KeyboardSession(
            nowMs = { clock.now },
            listen = ContinuousListenController(segmentedSessionAvailable = false),
            commit = { inserted += it },
        )
    }
}
