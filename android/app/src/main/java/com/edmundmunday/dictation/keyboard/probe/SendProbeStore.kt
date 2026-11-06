package com.edmundmunday.dictation.keyboard.probe

import android.view.inputmethod.EditorInfo
import java.io.File

data class SendProbeRecord(val packageName: String, val send: Boolean)

object SendProbeFiles {
    const val FILE_NAME = "send-probe.txt"
}

class SendProbeStore(private val file: File) {
    fun note(packageName: String, imeOptions: Int): SendProbeRecord {
        if (packageName.isBlank() || packageName.any { it.isWhitespace() }) {
            error("send probe: package name missing")
        }
        val record = SendProbeRecord(packageName, hasSendAction(imeOptions))
        file.parentFile?.mkdirs()
        try {
            file.appendText("${record.packageName}\t${if (record.send) "yes" else "no"}\n")
        } catch (error: Exception) {
            error("send probe write failed: ${file.path}: ${error.message}")
        }
        return record
    }

    fun list(): List<SendProbeRecord> {
        if (!file.exists()) return emptyList()
        val text = try {
            file.readText()
        } catch (error: Exception) {
            error("send probe read failed: ${file.path}: ${error.message}")
        }
        if (text.isBlank()) return emptyList()
        return text.lineSequence().filter { it.isNotBlank() }.map { parse(it) }.toList()
    }

    private fun parse(line: String): SendProbeRecord {
        val parts = line.split('\t')
        if (parts.size != 2 || (parts[1] != "yes" && parts[1] != "no") || parts[0].isBlank()) {
            error("send probe read failed: ${file.path}: bad record")
        }
        return SendProbeRecord(parts[0], parts[1] == "yes")
    }
}

fun hasSendAction(imeOptions: Int): Boolean {
    val action = imeOptions and EditorInfo.IME_MASK_ACTION
    return action == EditorInfo.IME_ACTION_SEND
}
