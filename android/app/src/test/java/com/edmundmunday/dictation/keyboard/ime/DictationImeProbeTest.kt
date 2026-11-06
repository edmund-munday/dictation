package com.edmundmunday.dictation.keyboard.ime

import android.view.inputmethod.EditorInfo
import com.edmundmunday.dictation.keyboard.probe.SendProbeFiles
import com.edmundmunday.dictation.keyboard.probe.SendProbeRecord
import com.edmundmunday.dictation.keyboard.probe.SendProbeStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DictationImeProbeTest {
    @Test
    fun `attaching to a field records the package and send and never the field text`() {
        val service = Robolectric.buildService(DictationImeService::class.java).create().get()
        val info = EditorInfo()
        info.packageName = "com.whatsapp"
        info.imeOptions = EditorInfo.IME_ACTION_SEND or EditorInfo.IME_FLAG_NO_EXTRACT_UI
        info.hintText = "secret-field-text"
        info.label = "secret-field-text"
        info.privateImeOptions = "secret-field-text"
        info.actionLabel = "secret-field-text"
        info.fieldName = "secret-field-text"
        service.onStartInput(info, false)

        val file = File(service.filesDir, SendProbeFiles.FILE_NAME)
        val records = SendProbeStore(file).list()
        assertEquals(listOf(SendProbeRecord("com.whatsapp", true)), records)
        val raw = file.readText()
        assertFalse(raw.contains("secret-field-text"))
        assertFalse(raw.contains("hint"))
    }
}
