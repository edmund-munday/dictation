package com.edmundmunday.dictation.keyboard.recogniser

/**
 * Keeps one take listening across pauses.
 *
 * When the recogniser delivers segmented results, those are committed and a
 * pause does not start a new session. Otherwise the session is restarted
 * after end-of-speech or a silence error, and the next words are joined on
 * to the ones already kept. Overlap at the join is dropped so words are not
 * repeated; words that do not overlap are kept.
 */
class ContinuousListenController(private val segmentedSessionAvailable: Boolean) {
    var display: String = ""
        private set

    var transcript: String = ""
        private set

    var restartCount: Int = 0
        private set

    private val committed = mutableListOf<SpokenWord>()
    private var partial: List<SpokenWord> = emptyList()
    private var listening = false
    private var acceptLateFinal = false
    private var cancelled = false
    private var seenSegment = false
    private var speechEnded = false
    private var sessionFinalReceived = false
    private var finalSeen = false

    /** True once a segment or session final is in, and no partial is still open. */
    val hasFinal: Boolean
        get() = finalSeen && partial.isEmpty()

    fun start() {
        committed.clear()
        partial = emptyList()
        listening = true
        acceptLateFinal = false
        cancelled = false
        seenSegment = false
        speechEnded = false
        sessionFinalReceived = false
        finalSeen = false
        restartCount = 0
        refresh()
    }

    fun stop() {
        listening = false
        acceptLateFinal = true
        refresh()
    }

    fun cancel() {
        listening = false
        acceptLateFinal = false
        cancelled = true
        committed.clear()
        partial = emptyList()
        finalSeen = false
        refresh()
    }

    fun onPartial(text: String) {
        if (!open()) return
        partial = spokenWords(text)
        refresh()
    }

    fun onSegment(text: String) {
        if (!open()) return
        seenSegment = true
        partial = emptyList()
        commit(spokenWords(text))
        finalSeen = true
        refresh()
    }

    fun onSessionFinal(text: String) {
        if (!open()) return
        partial = emptyList()
        commit(spokenWords(text))
        sessionFinalReceived = true
        finalSeen = true
        refresh()
        if (listening && !seenSegment && speechEnded) restart()
    }

    fun onEndOfSpeech() {
        if (!listening || cancelled || seenSegment) return
        speechEnded = true
        if (sessionFinalReceived) restart()
    }

    fun onSilence() {
        if (!listening || cancelled || seenSegment) return
        restart()
    }

    fun onEndOfSegmentedSession() {
        if (!listening || cancelled) return
        if (!segmentedSessionAvailable && !seenSegment) return
        restart()
    }

    private fun open(): Boolean = !cancelled && (listening || acceptLateFinal)

    private fun restart() {
        restartCount += 1
        partial = emptyList()
        speechEnded = false
        sessionFinalReceived = false
        refresh()
    }

    private fun commit(incoming: List<SpokenWord>) {
        if (incoming.isEmpty()) return
        committed.addAll(incoming.drop(overlapCount(committed, incoming)))
    }

    private fun refresh() {
        val shown = ArrayList<SpokenWord>(committed.size + partial.size)
        shown.addAll(committed)
        shown.addAll(partial.drop(overlapCount(committed, partial)))
        val text = joinWords(shown)
        display = text
        transcript = text
    }
}
