package com.edmundmunday.dictation.keyboard.bench

import java.io.File

object Phrases {
    fun defaultFile(): File {
        val start = File(System.getProperty("user.dir") ?: ".")
        val relative = listOf(
            "bench/phrases.txt",
            "../bench/phrases.txt",
            "android/bench/phrases.txt",
        )
        val candidates = ArrayList<File>()
        var dir: File? = start
        while (dir != null) {
            for (name in relative) candidates.add(File(dir, name))
            dir = dir.parentFile
        }
        return candidates.firstOrNull { it.isFile }
            ?: error("phrases.txt missing: looked in ${candidates.joinToString { it.path }}")
    }

    fun load(file: File): List<String> {
        if (!file.isFile) error("phrases.txt missing: ${file.path}")
        val text = try {
            file.readText()
        } catch (error: Exception) {
            error("phrases.txt read failed: ${file.path}: ${error.message}")
        }
        return parse(text, file.path)
    }

    fun parse(text: String, source: String): List<String> {
        val lines = text.split('\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
        if (lines.size != 20) {
            error("phrases.txt: expected 20 phrases, found ${lines.size}: $source")
        }
        return lines
    }
}
