package com.edmundmunday.dictation.keyboard.ime

import android.Manifest
import android.content.pm.PackageManager
import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.TextView
import com.edmundmunday.dictation.keyboard.R
import com.edmundmunday.dictation.keyboard.recogniser.AndroidLiveRecognizer
import com.edmundmunday.dictation.keyboard.recogniser.ContinuousListenController
import com.edmundmunday.dictation.keyboard.recogniser.RecogniserChoice
import com.edmundmunday.dictation.keyboard.recogniser.RecogniserPrefs
import com.edmundmunday.dictation.keyboard.session.KeyboardSession
import com.edmundmunday.dictation.keyboard.take.TakeState
import com.edmundmunday.dictation.keyboard.whisper.WhisperCppTranscriber
import com.edmundmunday.dictation.keyboard.whisper.WhisperModel
import com.edmundmunday.dictation.keyboard.whisper.WhisperModels
import com.edmundmunday.dictation.keyboard.audio.InMemoryPcm
import com.edmundmunday.dictation.keyboard.probe.SendProbeFiles
import com.edmundmunday.dictation.keyboard.probe.SendProbeStore
import java.io.File
import java.util.concurrent.Executors

class DictationImeService : InputMethodService() {
    private val handler = Handler(Looper.getMainLooper())
    private val benchWorker = Executors.newSingleThreadExecutor()
    private var session: KeyboardSession? = null
    private var live: AndroidLiveRecognizer? = null
    private var whisper: WhisperCppTranscriber? = null
    private var whisperFile: File? = null
    private var capture: InMemoryPcm? = null
    private var stripView: TextView? = null
    private var talkButton: Button? = null
    private var ticking = false
    private var holdStrip = false

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        if (attribute != null) {
            val packageName = attribute.packageName
            if (!packageName.isNullOrBlank()) {
                SendProbeStore(File(filesDir, SendProbeFiles.FILE_NAME))
                    .note(packageName, attribute.imeOptions)
            }
        }
        super.onStartInput(attribute, restarting)
    }

    override fun onCreateInputView(): View {
        val root = layoutInflater.inflate(R.layout.keyboard, null)
        stripView = root.findViewById(R.id.strip)
        talkButton = root.findViewById(R.id.talk)
        val switchKey = root.findViewById<Button>(R.id.switch_key)
        session = KeyboardSession(
            nowMs = { System.currentTimeMillis() },
            listen = ContinuousListenController(segmentedSessionAvailable = true),
            commit = { text -> currentInputConnection?.commitText(text, 1) },
        )
        talkButton?.setOnClickListener {
            it.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            onTalk()
        }
        switchKey.setOnClickListener { switchToPreviousInputMethod() }
        refresh()
        return root
    }

    override fun onDestroy() {
        stopTick()
        live?.cancel()
        capture?.let { runCatching { it.stop() } }
        whisper?.close()
        benchWorker.shutdownNow()
        super.onDestroy()
    }

    private fun onTalk() {
        val current = session ?: return
        holdStrip = false
        if (current.state == TakeState.PROCESSING) {
            current.cancel()
            abandon()
            refresh()
            return
        }
        if (!microphoneAllowed()) {
            show("Microphone permission is off: open setup.")
            return
        }
        val choice = try {
            RecogniserPrefs.read(this)
        } catch (error: IllegalStateException) {
            show(error.message ?: "recogniser preference failed")
            return
        }
        val before = current.state
        if (before == TakeState.READY && choice != RecogniserChoice.ANDROID_ON_DEVICE) {
            val model = whisperModel(choice)
            val file = WhisperModels.file(filesDir, model)
            if (!file.isFile) {
                show("Speech model not downloaded: open setup.")
                return
            }
        }
        current.tapTalk()
        when {
            before == TakeState.READY && current.state == TakeState.LISTENING -> begin(choice)
            before == TakeState.LISTENING && current.state == TakeState.READY -> abandon()
            before == TakeState.LISTENING && current.state == TakeState.PROCESSING -> finish(choice)
        }
        refresh()
    }

    private fun begin(choice: RecogniserChoice) {
        startTick()
        if (choice == RecogniserChoice.ANDROID_ON_DEVICE) {
            val current = session ?: return
            val recogniser = AndroidLiveRecognizer(
                context = this,
                session = current,
                segmentedSessionAvailable = true,
                onFailure = { message ->
                    handler.post {
                        session?.cancel()
                        abandon()
                        refresh()
                        show(message)
                    }
                },
                onDisplay = { handler.post { refresh() } },
            )
            live = recogniser
            recogniser.start()
        } else {
            val pcm = InMemoryPcm()
            try {
                pcm.start()
            } catch (error: IllegalStateException) {
                session?.cancel()
                stopTick()
                show(error.message ?: "AudioRecord: microphone unavailable")
                return
            }
            capture = pcm
        }
    }

    private fun finish(choice: RecogniserChoice) {
        stopTick()
        if (choice == RecogniserChoice.ANDROID_ON_DEVICE) {
            live?.stop()
            return
        }
        val pcm = capture?.stop() ?: ShortArray(0)
        capture = null
        val model = whisperModel(choice)
        val file = WhisperModels.file(filesDir, model)
        if (whisper == null || whisperFile != file) {
            whisper?.close()
            whisper = WhisperCppTranscriber(choice.stored, file)
            whisperFile = file
        }
        val engine = whisper ?: return
        benchWorker.execute {
            val text = try {
                engine.transcribe(pcm, InMemoryPcm.SAMPLE_RATE)
            } catch (error: Exception) {
                handler.post {
                    session?.cancel()
                    abandon()
                    refresh()
                    show(error.message ?: "whisper transcription failed")
                }
                return@execute
            }
            handler.post {
                session?.onSessionFinal(text)
                refresh()
            }
        }
    }

    private fun abandon() {
        stopTick()
        live?.cancel()
        live = null
        capture?.let { runCatching { it.stop() } }
        capture = null
    }

    private fun whisperModel(choice: RecogniserChoice): WhisperModel {
        return when (choice) {
            RecogniserChoice.WHISPER_SMALL -> WhisperModel.SMALL
            RecogniserChoice.WHISPER_BASE -> WhisperModel.BASE
            RecogniserChoice.ANDROID_ON_DEVICE -> error("whisper model requested for the Android recogniser")
        }
    }

    private fun startTick() {
        if (ticking) return
        ticking = true
        handler.post(tick)
    }

    private fun stopTick() {
        ticking = false
        handler.removeCallbacks(tick)
    }

    private val tick = object : Runnable {
        override fun run() {
            if (!ticking) return
            val current = session ?: return
            val before = current.state
            current.onTime()
            if (before == TakeState.LISTENING && current.state == TakeState.PROCESSING) {
                ticking = false
                val choice = runCatching { RecogniserPrefs.read(this@DictationImeService) }
                    .getOrDefault(RecogniserChoice.ANDROID_ON_DEVICE)
                finish(choice)
            }
            refresh()
            if (ticking) handler.postDelayed(this, TICK_MS)
        }
    }

    private fun refresh() {
        if (holdStrip) return
        val current = session
        stripView?.text = current?.strip ?: "Tap to talk"
        talkButton?.text = when (current?.state) {
            TakeState.LISTENING -> "Stop"
            TakeState.PROCESSING -> "Cancel"
            else -> "Talk"
        }
        talkButton?.isEnabled = true
    }

    private fun show(message: String) {
        holdStrip = true
        stripView?.text = message
    }

    private fun microphoneAllowed(): Boolean {
        return checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        private const val TICK_MS = 250L
    }
}
