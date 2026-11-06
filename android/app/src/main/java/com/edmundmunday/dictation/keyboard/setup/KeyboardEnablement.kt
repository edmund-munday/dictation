package com.edmundmunday.dictation.keyboard.setup

import android.content.ComponentName
import android.content.Context
import android.view.inputmethod.InputMethodManager

class KeyboardEnablement(
    private val enabledComponents: () -> List<ComponentName>,
) {
    fun isEnabled(service: ComponentName): Boolean {
        return enabledComponents().any { it == service }
    }
}

// Settings.Secure.ENABLED_INPUT_METHODS throws SecurityException when targetSdk is above 33.
fun keyboardEnablement(context: Context): KeyboardEnablement {
    return KeyboardEnablement {
        val manager = context.getSystemService(InputMethodManager::class.java)
            ?: return@KeyboardEnablement emptyList()
        manager.enabledInputMethodList.orEmpty().map { it.component }
    }
}
