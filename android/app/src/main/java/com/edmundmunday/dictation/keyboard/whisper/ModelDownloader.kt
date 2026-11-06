package com.edmundmunday.dictation.keyboard.whisper

import java.io.File
import java.net.HttpURLConnection
import java.net.URL

object ModelDownloader {
    fun download(model: WhisperModel, filesDir: File): File {
        val dest = WhisperModels.file(filesDir, model)
        val directory = dest.parentFile ?: error("model download failed: no models directory")
        if (!directory.isDirectory && !directory.mkdirs()) {
            error("model download failed: could not create ${directory.path}")
        }
        val url = WhisperModels.url(model)
        val partial = File(directory, dest.name + ".part")
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 15_000
            readTimeout = 60_000
        }
        try {
            connection.connect()
            if (connection.responseCode !in 200..299) {
                error("model download failed: $url: HTTP ${connection.responseCode}")
            }
            connection.inputStream.use { input ->
                partial.outputStream().use { output -> input.copyTo(output) }
            }
        } catch (error: Exception) {
            partial.delete()
            if (error is IllegalStateException) throw error
            error("model download failed: $url: ${error.message}")
        } finally {
            connection.disconnect()
        }
        val size = partial.length()
        if (size < MIN_BYTES) {
            partial.delete()
            error("model download failed: $url: file too small ($size bytes)")
        }
        if (dest.exists() && !dest.delete()) {
            partial.delete()
            error("model download failed: could not replace ${dest.path}")
        }
        if (!partial.renameTo(dest)) {
            partial.delete()
            error("model download failed: could not store ${dest.path}")
        }
        return dest
    }

    private const val MIN_BYTES = 1_000_000L
}
