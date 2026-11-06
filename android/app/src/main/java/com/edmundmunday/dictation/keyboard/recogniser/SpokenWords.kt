package com.edmundmunday.dictation.keyboard.recogniser

internal data class SpokenWord(val text: String, val key: String)

internal fun spokenWords(text: String): List<SpokenWord> {
    if (text.isBlank()) return emptyList()
    return text.split(Regex("\\s+")).mapNotNull { raw ->
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return@mapNotNull null
        val key = trimmed.lowercase().filter { it.isLetterOrDigit() || it == '\'' }
        if (key.isEmpty()) null else SpokenWord(trimmed, key)
    }
}

/** Longest suffix of [committed] that equals the prefix of [incoming], by word key. */
internal fun overlapCount(committed: List<SpokenWord>, incoming: List<SpokenWord>): Int {
    val max = minOf(committed.size, incoming.size)
    for (size in max downTo 1) {
        var same = true
        for (index in 0 until size) {
            if (committed[committed.size - size + index].key != incoming[index].key) {
                same = false
                break
            }
        }
        if (same) return size
    }
    return 0
}

internal fun joinWords(words: List<SpokenWord>): String = words.joinToString(" ") { it.text }
