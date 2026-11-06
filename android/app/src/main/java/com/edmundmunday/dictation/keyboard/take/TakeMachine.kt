package com.edmundmunday.dictation.keyboard.take

/**
 * One dictation take. The caller supplies the clock so the 300 ms floor and
 * the 120 s cap can be tested without waiting.
 */
class TakeMachine(private val nowMs: () -> Long) {
    var state: TakeState = TakeState.READY
        private set

    var strip: String = READY_STRIP
        private set

    private var startedAtMs: Long = 0L
    private var pendingInsert: String? = null

    fun tapTalk() {
        onTime()
        when (state) {
            TakeState.READY -> {
                state = TakeState.LISTENING
                startedAtMs = nowMs()
                strip = LISTENING_STRIP
            }
            TakeState.LISTENING -> {
                if (nowMs() - startedAtMs < MIN_TAKE_MS) {
                    toReady()
                } else {
                    state = TakeState.PROCESSING
                }
            }
            TakeState.PROCESSING -> Unit
        }
    }

    fun cancel() {
        if (state == TakeState.READY) return
        pendingInsert = null
        toReady()
    }

    fun onTime() {
        if (state != TakeState.LISTENING) return
        if (nowMs() - startedAtMs >= MAX_TAKE_MS) {
            state = TakeState.PROCESSING
            strip = MAX_LENGTH_STRIP
        }
    }

    fun onPartial(text: String) {
        if (state != TakeState.LISTENING) return
        strip = text
    }

    fun onFinal(text: String) {
        if (state != TakeState.PROCESSING) return
        if (text.isNotBlank()) pendingInsert = text
        toReady()
    }

    fun consumeInsert(): String? {
        val text = pendingInsert
        pendingInsert = null
        return text
    }

    private fun toReady() {
        state = TakeState.READY
        strip = READY_STRIP
    }

    companion object {
        const val MIN_TAKE_MS = 300L
        const val MAX_TAKE_MS = 120_000L
        const val READY_STRIP = "Tap to talk"
        const val LISTENING_STRIP = "Listening..."
        const val MAX_LENGTH_STRIP = "Maximum length reached."
    }
}
