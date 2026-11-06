package com.edmundmunday.dictation.keyboard.probe

import android.view.inputmethod.EditorInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class SendProbeTest {
    @Test
    fun `a send action is recorded for the package`() {
        val store = SendProbeStore(tempFile())
        val record = store.note("com.whatsapp", EditorInfo.IME_ACTION_SEND)
        assertEquals(SendProbeRecord("com.whatsapp", true), record)
        assertEquals(listOf(record), store.list())
    }

    @Test
    fun `flags beside send do not hide the send action`() {
        val options = EditorInfo.IME_ACTION_SEND or
            EditorInfo.IME_FLAG_NO_EXTRACT_UI or
            EditorInfo.IME_FLAG_NO_FULLSCREEN
        val record = SendProbeStore(tempFile()).note("com.whatsapp", options)
        assertTrue(record.send)
    }

    @Test
    fun `search go and an unspecified action are not send`() {
        val store = SendProbeStore(tempFile())
        assertFalse(store.note("com.android.chrome", EditorInfo.IME_ACTION_SEARCH).send)
        assertFalse(store.note("com.google.android.apps.maps", EditorInfo.IME_ACTION_GO).send)
        assertFalse(store.note("com.android.mms", EditorInfo.IME_ACTION_UNSPECIFIED).send)
    }

    @Test
    fun `the list keeps package and send in attachment order`() {
        val store = SendProbeStore(tempFile())
        store.note("org.thoughtcrime.securesms", EditorInfo.IME_ACTION_SEND)
        store.note("com.android.chrome", EditorInfo.IME_ACTION_SEARCH)
        assertEquals(
            listOf(
                SendProbeRecord("org.thoughtcrime.securesms", true),
                SendProbeRecord("com.android.chrome", false),
            ),
            store.list(),
        )
    }

    @Test
    fun `a blank package name fails the record`() {
        val error = runCatching {
            SendProbeStore(tempFile()).note("  ", EditorInfo.IME_ACTION_SEND)
        }.exceptionOrNull()
        assertTrue(error is IllegalStateException)
        assertTrue(error!!.message!!.contains("package"))
    }

    @Test
    fun `a corrupt probe file fails the read and names the file`() {
        val file = tempFile()
        file.writeText("this is not a probe record\n")
        val error = runCatching { SendProbeStore(file).list() }.exceptionOrNull()
        assertTrue(error is IllegalStateException)
        assertTrue(error!!.message!!.contains(file.path))
    }

    @Test
    fun `a missing probe file means nothing has been recorded`() {
        val missing = File("/tmp/dictation-send-probe-missing.txt")
        missing.delete()
        assertEquals(emptyList<SendProbeRecord>(), SendProbeStore(missing).list())
    }

    private fun tempFile(): File = File.createTempFile("send-probe", ".txt")
}
