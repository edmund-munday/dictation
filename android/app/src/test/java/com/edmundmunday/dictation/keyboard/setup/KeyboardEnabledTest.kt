package com.edmundmunday.dictation.keyboard.setup

import android.content.ComponentName
import android.view.inputmethod.InputMethodInfo
import android.view.inputmethod.InputMethodManager
import android.widget.TextView
import com.edmundmunday.dictation.keyboard.R
import com.edmundmunday.dictation.keyboard.ime.DictationImeService
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class KeyboardEnabledTest {
    private val service = ComponentName(
        "com.edmundmunday.dictation.keyboard",
        "com.edmundmunday.dictation.keyboard.ime.DictationImeService",
    )

    @Test
    fun `enabled when the enabled input method list contains this service`() {
        val other = ComponentName(
            "com.google.android.inputmethod.latin",
            "com.android.inputmethod.latin.LatinIME",
        )
        val checker = KeyboardEnablement { listOf(other, service) }

        assertTrue(checker.isEnabled(service))
    }

    @Test
    fun `not enabled when this service is absent from the enabled input method list`() {
        val other = ComponentName(
            "com.google.android.inputmethod.latin",
            "com.android.inputmethod.latin.LatinIME",
        )
        val samePackage = ComponentName(service.packageName, "${service.packageName}.OtherIme")

        assertFalse(KeyboardEnablement { listOf(other) }.isEnabled(service))
        assertFalse(KeyboardEnablement { listOf(samePackage) }.isEnabled(service))
        assertFalse(KeyboardEnablement { emptyList() }.isEnabled(service))
    }

    @Test
    fun `setup reads the enabled keyboard from InputMethodManager`() {
        val controller = Robolectric.buildActivity(SetupActivity::class.java).setup()
        val activity = controller.get()
        val service = ComponentName(activity, DictationImeService::class.java)
        val manager = activity.getSystemService(InputMethodManager::class.java)
        shadowOf(manager).setEnabledInputMethodInfoList(listOf(inputMethod(service)))

        controller.pause().resume()

        assertEquals(
            "Keyboard: enabled",
            activity.findViewById<TextView>(R.id.keyboard_status).text.toString(),
        )
    }

    @Test
    fun `setup reports the keyboard not enabled when InputMethodManager omits it`() {
        val controller = Robolectric.buildActivity(SetupActivity::class.java).setup()
        val activity = controller.get()
        val manager = activity.getSystemService(InputMethodManager::class.java)
        val other = ComponentName(
            "com.google.android.inputmethod.latin",
            "com.android.inputmethod.latin.LatinIME",
        )
        shadowOf(manager).setEnabledInputMethodInfoList(listOf(inputMethod(other)))

        controller.pause().resume()

        assertEquals(
            "Keyboard: not enabled",
            activity.findViewById<TextView>(R.id.keyboard_status).text.toString(),
        )
    }

    private fun inputMethod(component: ComponentName): InputMethodInfo {
        return InputMethodInfo(component.packageName, component.className, "keyboard", "")
    }
}
