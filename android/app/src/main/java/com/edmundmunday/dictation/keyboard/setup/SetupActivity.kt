package com.edmundmunday.dictation.keyboard.setup

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.widget.Button
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import androidx.core.content.FileProvider
import com.edmundmunday.dictation.keyboard.R
import com.edmundmunday.dictation.keyboard.audio.InMemoryPcm
import com.edmundmunday.dictation.keyboard.bench.BenchReport
import com.edmundmunday.dictation.keyboard.bench.PhraseScore
import com.edmundmunday.dictation.keyboard.bench.Phrases
import com.edmundmunday.dictation.keyboard.bench.PcmTranscriber
import com.edmundmunday.dictation.keyboard.bench.SameAudioBench
import com.edmundmunday.dictation.keyboard.bench.scorePhrase
import com.edmundmunday.dictation.keyboard.ime.DictationImeService
import com.edmundmunday.dictation.keyboard.probe.SendProbeFiles
import com.edmundmunday.dictation.keyboard.probe.SendProbeStore
import com.edmundmunday.dictation.keyboard.recogniser.AndroidPcmTranscriber
import com.edmundmunday.dictation.keyboard.recogniser.RecogniserChoice
import com.edmundmunday.dictation.keyboard.recogniser.RecogniserPrefs
import com.edmundmunday.dictation.keyboard.whisper.ModelDownloader
import com.edmundmunday.dictation.keyboard.whisper.WhisperCppTranscriber
import com.edmundmunday.dictation.keyboard.whisper.WhisperModel
import com.edmundmunday.dictation.keyboard.whisper.WhisperModels
import java.io.File
import java.util.concurrent.Executors

class SetupActivity : android.app.Activity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var phrases: List<String> = emptyList()
    private var phraseIndex = 0
    private val scores = ArrayList<PhraseScore>()
    private var capture: InMemoryPcm? = null
    private var recording = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_setup)
        phrases = loadPhrases()
        findViewById<Button>(R.id.enable_keyboard).setOnClickListener {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
        }
        findViewById<Button>(R.id.grant_microphone).setOnClickListener {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQUEST)
        }
        findViewById<Button>(R.id.download_small).setOnClickListener { download(WhisperModel.SMALL) }
        findViewById<Button>(R.id.download_base).setOnClickListener { download(WhisperModel.BASE) }
        findViewById<Button>(R.id.record_take).setOnClickListener { onRecord() }
        findViewById<Button>(R.id.export_results).setOnClickListener { export() }
        val radios = findViewById<RadioGroup>(R.id.recogniser_picker)
        val current = runCatching { RecogniserPrefs.read(this) }.getOrNull()
        radios.check(radioId(current ?: RecogniserChoice.ANDROID_ON_DEVICE))
        radios.setOnCheckedChangeListener { _, checkedId ->
            val choice = choiceFor(checkedId) ?: return@setOnCheckedChangeListener
            RecogniserPrefs.write(this, choice)
        }
        showPhrase()
    }

    override fun onResume() {
        super.onResume()
        refreshStatus()
    }

    override fun onDestroy() {
        if (recording) runCatching { capture?.stop() }
        worker.shutdownNow()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        refreshStatus()
    }

    private fun refreshStatus() {
        val enabled = imeEnabled()
        findViewById<TextView>(R.id.keyboard_status).text =
            if (enabled) "Keyboard: enabled" else "Keyboard: not enabled"
        val mic = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        findViewById<TextView>(R.id.microphone_status).text =
            if (mic) "Microphone: granted" else "Microphone: not granted"
        findViewById<TextView>(R.id.model_status).text = modelStatus()
        findViewById<TextView>(R.id.probe_list).text = probeText()
    }

    private fun imeEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_INPUT_METHODS)
            ?: return false
        val flat = ComponentName(this, DictationImeService::class.java).flattenToString()
        return enabled.split(':').any { it.substringBefore(';') == flat }
    }

    private fun modelStatus(): String {
        fun line(model: WhisperModel): String {
            val file = WhisperModels.file(filesDir, model)
            val state = if (file.isFile) "ready (${file.length()} bytes)" else "not downloaded"
            return "${WhisperModels.fileName(model)}: $state"
        }
        return line(WhisperModel.SMALL) + "\n" + line(WhisperModel.BASE)
    }

    private fun probeText(): String {
        return try {
            val records = SendProbeStore(File(filesDir, SendProbeFiles.FILE_NAME)).list()
            if (records.isEmpty()) {
                "No fields seen yet."
            } else {
                records.joinToString("\n") { record ->
                    "${record.packageName}  Send ${if (record.send) "yes" else "no"}"
                }
            }
        } catch (error: IllegalStateException) {
            error.message ?: "send probe read failed"
        }
    }

    private fun download(model: WhisperModel) {
        val status = findViewById<TextView>(R.id.model_status)
        status.text = "Downloading ${WhisperModels.fileName(model)}..."
        worker.execute {
            val message = try {
                ModelDownloader.download(model, filesDir)
                modelStatus()
            } catch (error: Exception) {
                error.message ?: "model download failed"
            }
            runOnUiThread {
                status.text = message
            }
        }
    }

    private fun onRecord() {
        if (phrases.isEmpty()) return
        if (!recording) {
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                findViewById<TextView>(R.id.bench_result).text = "Microphone permission is off."
                return
            }
            val pcm = InMemoryPcm()
            try {
                pcm.start()
            } catch (error: IllegalStateException) {
                findViewById<TextView>(R.id.bench_result).text = error.message
                return
            }
            capture = pcm
            recording = true
            findViewById<Button>(R.id.record_take).text = "Stop"
            findViewById<TextView>(R.id.bench_result).text = "Listening..."
            return
        }
        recording = false
        findViewById<Button>(R.id.record_take).isEnabled = false
        val pcm = try {
            capture?.stop() ?: ShortArray(0)
        } catch (error: IllegalStateException) {
            findViewById<TextView>(R.id.bench_result).text = error.message
            findViewById<Button>(R.id.record_take).isEnabled = true
            return
        }
        capture = null
        val reference = phrases[phraseIndex]
        findViewById<TextView>(R.id.bench_result).text = "Scoring the take..."
        worker.execute {
            val message = try {
                val score = scoreTake(reference, pcm)
                scores.add(score)
                phraseIndex += 1
                formatScore(score)
            } catch (error: Exception) {
                error.message ?: "bench take failed"
            }
            runOnUiThread {
                findViewById<TextView>(R.id.bench_result).text = message
                findViewById<Button>(R.id.record_take).isEnabled = phraseIndex < phrases.size
                findViewById<Button>(R.id.record_take).text = "Record"
                showPhrase()
                if (phraseIndex >= phrases.size) showOverall()
            }
        }
    }

    private fun scoreTake(reference: String, pcm: ShortArray): PhraseScore {
        val transcribers = ArrayList<PcmTranscriber>()
        transcribers.add(AndroidPcmTranscriber(this))
        for (model in listOf(WhisperModel.SMALL, WhisperModel.BASE)) {
            val file = WhisperModels.file(filesDir, model)
            if (!file.isFile) error("whisper model missing: ${file.path}")
            val id = if (model == WhisperModel.SMALL) "whisper-small" else "whisper-base"
            transcribers.add(WhisperCppTranscriber(id, file))
        }
        val results = SameAudioBench(transcribers) { SystemClock.elapsedRealtime() }
            .transcribe(pcm, InMemoryPcm.SAMPLE_RATE)
        return scorePhrase(reference, results)
    }

    private fun formatScore(score: PhraseScore): String {
        return score.results.joinToString("\n") { result ->
            val percent = (result.wer.rate * 1000).toInt() / 10.0
            "${result.id}: WER $percent%  ${result.stopToFinalMs} ms\n${result.hypothesis}"
        }
    }

    private fun showPhrase() {
        val view = findViewById<TextView>(R.id.bench_phrase)
        if (phrases.isEmpty()) return
        if (phraseIndex >= phrases.size) {
            view.text = "Bench complete."
            return
        }
        view.text = "Phrase ${phraseIndex + 1} of ${phrases.size}\n${phrases[phraseIndex]}"
    }

    private fun showOverall() {
        val report = BenchReport(scores)
        val lines = scores.flatMap { it.results.map { result -> result.id } }.distinct().map { id ->
            val overall = report.overall(id)
            val percent = (overall.rate * 1000).toInt() / 10.0
            "$id overall WER $percent% (${overall.errors}/${overall.referenceWords})"
        }
        val current = findViewById<TextView>(R.id.bench_result).text
        findViewById<TextView>(R.id.bench_result).text = current.toString() + "\n\n" + lines.joinToString("\n")
    }

    private fun export() {
        if (scores.isEmpty()) {
            findViewById<TextView>(R.id.bench_result).text = "No bench results to export."
            return
        }
        val json = BenchReport(scores).toJson()
        val dir = File(cacheDir, "bench")
        if (!dir.isDirectory && !dir.mkdirs()) {
            findViewById<TextView>(R.id.bench_result).text = "bench export failed: could not create ${dir.path}"
            return
        }
        val file = File(dir, "bench-results.json")
        try {
            file.writeText(json)
        } catch (error: Exception) {
            findViewById<TextView>(R.id.bench_result).text = "bench export failed: ${file.path}: ${error.message}"
            return
        }
        val uri: Uri = FileProvider.getUriForFile(this, "$packageName.files", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(send, "Export bench results"))
    }

    private fun loadPhrases(): List<String> {
        return try {
            val text = assets.open("phrases.txt").bufferedReader().use { it.readText() }
            Phrases.parse(text, "assets/phrases.txt")
        } catch (error: Exception) {
            findViewById<TextView>(R.id.bench_phrase).text = error.message ?: "phrases.txt read failed"
            emptyList()
        }
    }

    private fun radioId(choice: RecogniserChoice): Int {
        return when (choice) {
            RecogniserChoice.ANDROID_ON_DEVICE -> R.id.recogniser_android
            RecogniserChoice.WHISPER_SMALL -> R.id.recogniser_small
            RecogniserChoice.WHISPER_BASE -> R.id.recogniser_base
        }
    }

    private fun choiceFor(id: Int): RecogniserChoice? {
        return when (id) {
            R.id.recogniser_android -> RecogniserChoice.ANDROID_ON_DEVICE
            R.id.recogniser_small -> RecogniserChoice.WHISPER_SMALL
            R.id.recogniser_base -> RecogniserChoice.WHISPER_BASE
            else -> null
        }
    }

    companion object {
        private const val MIC_REQUEST = 1
    }
}
