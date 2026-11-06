package com.edmundmunday.dictation.keyboard.recogniser

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidRecognitionRequestTest {
    @Test
    fun `the on device request is Australian English with partials and no network`() {
        val request = androidRecognitionRequest(segmentedSessionAvailable = true)
        assertEquals("en-AU", request.language)
        assertTrue(request.partialResults)
        assertTrue(request.segmentedSession)
        assertTrue(request.onDeviceOnly)
    }

    @Test
    fun `segmented session is only requested when the recogniser offers it`() {
        val request = androidRecognitionRequest(segmentedSessionAvailable = false)
        assertFalse(request.segmentedSession)
        assertTrue(request.onDeviceOnly)
    }
}
