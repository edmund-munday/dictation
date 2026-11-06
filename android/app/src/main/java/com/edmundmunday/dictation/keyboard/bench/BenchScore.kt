package com.edmundmunday.dictation.keyboard.bench

interface PcmTranscriber {
    val id: String
    fun transcribe(pcm: ShortArray, sampleRate: Int): String
}

data class HypothesisResult(
    val id: String,
    val hypothesis: String,
    val stopToFinalMs: Long,
)

data class ScoredHypothesis(
    val id: String,
    val hypothesis: String,
    val wer: WerScore,
    val stopToFinalMs: Long,
)

data class PhraseScore(
    val reference: String,
    val results: List<ScoredHypothesis>,
)

class SameAudioBench(
    private val transcribers: List<PcmTranscriber>,
    private val nowMs: () -> Long,
) {
    fun transcribe(pcm: ShortArray, sampleRate: Int): List<HypothesisResult> {
        return transcribers.map { transcriber ->
            val started = nowMs()
            val text = try {
                transcriber.transcribe(pcm, sampleRate)
            } catch (error: Exception) {
                throw IllegalStateException(
                    "${transcriber.id} transcription failed: ${error.message}",
                    error,
                )
            }
            HypothesisResult(transcriber.id, text, nowMs() - started)
        }
    }
}

fun scorePhrase(reference: String, results: List<HypothesisResult>): PhraseScore {
    return PhraseScore(
        reference = reference,
        results = results.map { result ->
            ScoredHypothesis(
                id = result.id,
                hypothesis = result.hypothesis,
                wer = wordErrorRate(reference, result.hypothesis),
                stopToFinalMs = result.stopToFinalMs,
            )
        },
    )
}

class BenchReport(val phrases: List<PhraseScore>) {
    fun overall(id: String): WerScore {
        var substitutions = 0
        var deletions = 0
        var insertions = 0
        var words = 0
        var found = false
        for (phrase in phrases) {
            val match = phrase.results.find { it.id == id } ?: continue
            found = true
            substitutions += match.wer.substitutions
            deletions += match.wer.deletions
            insertions += match.wer.insertions
            words += match.wer.referenceWords
        }
        if (!found) error("bench overall: no results for $id")
        if (words == 0) error("bench overall: reference has no words for $id")
        return WerScore(substitutions, deletions, insertions, words)
    }

    fun toJson(): String {
        val phrasesJson = phrases.joinToString(",") { phrase ->
            val results = phrase.results.joinToString(",") { result ->
                val wer = result.wer
                "{" +
                    "\"id\":${jsonString(result.id)}," +
                    "\"hypothesis\":${jsonString(result.hypothesis)}," +
                    "\"substitutions\":${wer.substitutions}," +
                    "\"deletions\":${wer.deletions}," +
                    "\"insertions\":${wer.insertions}," +
                    "\"referenceWords\":${wer.referenceWords}," +
                    "\"errors\":${wer.errors}," +
                    "\"stopToFinalMs\":${result.stopToFinalMs}" +
                    "}"
            }
            "{\"reference\":${jsonString(phrase.reference)},\"results\":[$results]}"
        }
        val ids = phrases.flatMap { it.results.map { result -> result.id } }.distinct()
        val overall = ids.joinToString(",") { id ->
            val score = overall(id)
            "{\"id\":${jsonString(id)},\"errors\":${score.errors},\"referenceWords\":${score.referenceWords}}"
        }
        return "{\"phrases\":[$phrasesJson],\"overall\":[$overall]}"
    }
}

internal fun jsonString(value: String): String {
    val out = StringBuilder(value.length + 2)
    out.append('"')
    for (ch in value) {
        when (ch) {
            '\\' -> out.append("\\\\")
            '"' -> out.append("\\\"")
            '\n' -> out.append("\\n")
            '\r' -> out.append("\\r")
            '\t' -> out.append("\\t")
            else -> if (ch.code < 0x20) {
                out.append("\\u")
                out.append(ch.code.toString(16).padStart(4, '0'))
            } else {
                out.append(ch)
            }
        }
    }
    out.append('"')
    return out.toString()
}
