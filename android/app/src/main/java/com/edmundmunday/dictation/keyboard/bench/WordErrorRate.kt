package com.edmundmunday.dictation.keyboard.bench

data class WerScore(
    val substitutions: Int,
    val deletions: Int,
    val insertions: Int,
    val referenceWords: Int,
) {
    val errors: Int
        get() = substitutions + deletions + insertions

    val rate: Double
        get() {
            if (referenceWords == 0) error("word error rate: reference has no words")
            return errors.toDouble() / referenceWords.toDouble()
        }
}

fun wordErrorRate(reference: String, hypothesis: String): WerScore {
    val ref = tokenize(reference)
    val hyp = tokenize(hypothesis)
    if (ref.isEmpty()) error("word error rate: reference has no words")
    val rows = ref.size + 1
    val cols = hyp.size + 1
    val dist = Array(rows) { IntArray(cols) }
    val sub = Array(rows) { IntArray(cols) }
    val del = Array(rows) { IntArray(cols) }
    val ins = Array(rows) { IntArray(cols) }
    for (i in 1 until rows) {
        dist[i][0] = i
        del[i][0] = i
    }
    for (j in 1 until cols) {
        dist[0][j] = j
        ins[0][j] = j
    }
    for (i in 1 until rows) {
        for (j in 1 until cols) {
            val substitution = dist[i - 1][j - 1] + if (ref[i - 1] == hyp[j - 1]) 0 else 1
            val deletion = dist[i - 1][j] + 1
            val insertion = dist[i][j - 1] + 1
            if (substitution <= deletion && substitution <= insertion) {
                dist[i][j] = substitution
                sub[i][j] = sub[i - 1][j - 1] + if (ref[i - 1] == hyp[j - 1]) 0 else 1
                del[i][j] = del[i - 1][j - 1]
                ins[i][j] = ins[i - 1][j - 1]
            } else if (deletion <= insertion) {
                dist[i][j] = deletion
                sub[i][j] = sub[i - 1][j]
                del[i][j] = del[i - 1][j] + 1
                ins[i][j] = ins[i - 1][j]
            } else {
                dist[i][j] = insertion
                sub[i][j] = sub[i][j - 1]
                del[i][j] = del[i][j - 1]
                ins[i][j] = ins[i][j - 1] + 1
            }
        }
    }
    val lastRow = ref.size
    val lastCol = hyp.size
    return WerScore(sub[lastRow][lastCol], del[lastRow][lastCol], ins[lastRow][lastCol], ref.size)
}

internal fun tokenize(text: String): List<String> {
    return text.lowercase()
        .split(Regex("\\s+"))
        .map { it.trim { ch -> !ch.isLetterOrDigit() && ch != '\'' } }
        .filter { it.isNotEmpty() }
}
