package com.edmundmunday.dictation.keyboard.take

import com.edmundmunday.dictation.keyboard.support.FakeClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TakeMachineTest {
    @Test
    fun `a new take is ready and tells you to tap`() {
        val machine = TakeMachine { 0L }
        assertEquals(TakeState.READY, machine.state)
        assertEquals("Tap to talk", machine.strip)
        assertNull(machine.consumeInsert())
    }

    @Test
    fun `talk tap from ready starts listening`() {
        val machine = TakeMachine { 0L }
        machine.tapTalk()
        assertEquals(TakeState.LISTENING, machine.state)
        assertEquals("Listening...", machine.strip)
    }

    @Test
    fun `partial words replace the listening strip`() {
        val machine = TakeMachine { 0L }
        machine.tapTalk()
        machine.onPartial("ship it")
        assertEquals("ship it", machine.strip)
        machine.onPartial("ship it friday")
        assertEquals("ship it friday", machine.strip)
    }

    @Test
    fun `stop tap moves to processing and inserts the raw final transcript`() {
        val clock = FakeClock()
        val machine = TakeMachine { clock.now }
        machine.tapTalk()
        clock.now = 300
        machine.tapTalk()
        assertEquals(TakeState.PROCESSING, machine.state)
        machine.onFinal("um ship it friday actually I mean monday")
        assertEquals("um ship it friday actually I mean monday", machine.consumeInsert())
        assertEquals(TakeState.READY, machine.state)
        assertNull(machine.consumeInsert())
    }

    @Test
    fun `a take under 300 ms inserts nothing and ignores a late final`() {
        val clock = FakeClock()
        val machine = TakeMachine { clock.now }
        machine.tapTalk()
        clock.now = 299
        machine.tapTalk()
        assertEquals(TakeState.READY, machine.state)
        assertEquals("Tap to talk", machine.strip)
        machine.onFinal("hello")
        assertNull(machine.consumeInsert())
    }

    @Test
    fun `a take of exactly 300 ms is long enough to insert`() {
        val clock = FakeClock()
        val machine = TakeMachine { clock.now }
        machine.tapTalk()
        clock.now = 300
        machine.tapTalk()
        machine.onFinal("hello")
        assertEquals("hello", machine.consumeInsert())
    }

    @Test
    fun `cancel while listening inserts nothing`() {
        val clock = FakeClock()
        val machine = TakeMachine { clock.now }
        machine.tapTalk()
        clock.now = 2_000
        machine.onPartial("hello there")
        machine.cancel()
        assertEquals(TakeState.READY, machine.state)
        assertEquals("Tap to talk", machine.strip)
        machine.onFinal("hello there")
        assertNull(machine.consumeInsert())
    }

    @Test
    fun `cancel while processing inserts nothing and ignores a late final`() {
        val clock = FakeClock()
        val machine = TakeMachine { clock.now }
        machine.tapTalk()
        clock.now = 2_000
        machine.tapTalk()
        assertEquals(TakeState.PROCESSING, machine.state)
        machine.cancel()
        machine.onFinal("hello there")
        assertNull(machine.consumeInsert())
        assertEquals(TakeState.READY, machine.state)
    }

    @Test
    fun `the 120 second cap processes the take and says maximum length reached`() {
        val clock = FakeClock()
        val machine = TakeMachine { clock.now }
        machine.tapTalk()
        machine.onPartial("hello there")
        clock.now = 119_999
        machine.onTime()
        assertEquals(TakeState.LISTENING, machine.state)
        clock.now = 120_000
        machine.onTime()
        assertEquals(TakeState.PROCESSING, machine.state)
        assertEquals("Maximum length reached.", machine.strip)
        machine.onFinal("hello there friend")
        assertEquals("hello there friend", machine.consumeInsert())
    }

    @Test
    fun `a blank final inserts nothing`() {
        val clock = FakeClock()
        val machine = TakeMachine { clock.now }
        machine.tapTalk()
        clock.now = 1_000
        machine.tapTalk()
        machine.onFinal("   ")
        assertNull(machine.consumeInsert())
        assertEquals(TakeState.READY, machine.state)
    }

    @Test
    fun `a later take still inserts after a cancel`() {
        val clock = FakeClock()
        val machine = TakeMachine { clock.now }
        machine.tapTalk()
        clock.now = 1_000
        machine.cancel()
        machine.tapTalk()
        clock.now = 2_000
        machine.tapTalk()
        machine.onFinal("second")
        assertEquals("second", machine.consumeInsert())
    }
}
