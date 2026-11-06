package com.edmundmunday.dictation.keyboard.session

import com.edmundmunday.dictation.keyboard.recogniser.ContinuousListenController
import com.edmundmunday.dictation.keyboard.take.TakeMachine
import com.edmundmunday.dictation.keyboard.take.TakeState

/**
 * Connects the take state machine to the recogniser event stream.
 * Text is inserted only after a final transcript, and only when the take
 * was not cancelled or shorter than 300 ms.
 */
class KeyboardSession(
    nowMs: () -> Long,
    private val listen: ContinuousListenController,
    private val commit: (String) -> Unit,
) {
    private val machine = TakeMachine(nowMs)

    val strip: String
        get() = machine.strip

    val state: TakeState
        get() = machine.state

    val restartCount: Int
        get() = listen.restartCount

    fun tapTalk() {
        val before = machine.state
        machine.tapTalk()
        when {
            before == TakeState.READY && machine.state == TakeState.LISTENING -> listen.start()
            before == TakeState.LISTENING && machine.state == TakeState.READY -> listen.cancel()
            before == TakeState.LISTENING && machine.state == TakeState.PROCESSING -> {
                listen.stop()
                deliver()
            }
        }
    }

    fun cancel() {
        machine.cancel()
        listen.cancel()
    }

    fun onTime() {
        val before = machine.state
        machine.onTime()
        if (before == TakeState.LISTENING && machine.state == TakeState.PROCESSING) {
            listen.stop()
            deliver()
        }
    }

    fun onPartial(text: String) {
        if (machine.state != TakeState.LISTENING) return
        listen.onPartial(text)
        machine.onPartial(listen.display)
    }

    fun onSegment(text: String) {
        listen.onSegment(text)
        if (machine.state == TakeState.LISTENING) machine.onPartial(listen.display)
        deliver()
    }

    fun onSessionFinal(text: String) {
        listen.onSessionFinal(text)
        if (machine.state == TakeState.LISTENING) machine.onPartial(listen.display)
        deliver()
    }

    fun onEndOfSpeech() {
        listen.onEndOfSpeech()
    }

    fun onSilence() {
        listen.onSilence()
    }

    fun onEndOfSegmentedSession() {
        listen.onEndOfSegmentedSession()
    }

    private fun deliver() {
        if (machine.state != TakeState.PROCESSING) return
        if (!listen.hasFinal) return
        machine.onFinal(listen.transcript)
        machine.consumeInsert()?.let(commit)
    }
}
