package com.bbflight.background_downloader

import org.junit.Assert.assertEquals
import org.junit.Test

class HelpersTest {

    private fun task(headers: Map<String, String> = emptyMap()) = Task(
        taskId = "helpersTest",
        url = "https://example.com/file.zip",
        filename = "file.zip",
        headers = headers,
        baseDirectory = BaseDirectory.applicationDocuments,
        group = "default",
        updates = Updates.status,
        taskType = "DownloadTask"
    )

    @Test
    fun parseRangeReadsBothBounds() {
        assertEquals(Pair(10L, 20L), parseRange("bytes=10-20"))
    }

    @Test
    fun parseRangeSubstitutesZeroForMissingStart() {
        assertEquals(Pair(0L, 20L), parseRange("bytes=-20"))
    }

    @Test
    fun parseRangeReturnsNullForMissingEnd() {
        assertEquals(Pair(10L, null), parseRange("bytes=10-"))
    }

    @Test
    fun parseRangeReturnsZeroAndNullForUnparseableInput() {
        assertEquals(Pair(0L, null), parseRange(""))
        assertEquals(Pair(0L, null), parseRange("items=10-20"))
    }

    @Test
    fun contentLengthFromResponseHeader() {
        assertEquals(123L, getContentLength(mapOf("Content-Length" to listOf("123")), task()))
        assertEquals(123L, getContentLength(mapOf("content-length" to listOf("123")), task()))
    }

    @Test
    fun responseContentLengthTakesPrecedenceOverTaskHeaders() {
        val t = task(mapOf("Range" to "bytes=0-20", "Known-Content-Length" to "456"))
        assertEquals(123L, getContentLength(mapOf("Content-Length" to listOf("123")), t))
    }

    @Test
    fun unparseableResponseContentLengthFallsThroughToTaskHeaders() {
        val t = task(mapOf("Range" to "bytes=0-20"))
        assertEquals(21L, getContentLength(mapOf("Content-Length" to listOf("abc")), t))
    }

    @Test
    fun contentLengthFromRangeHeaderIsInclusive() {
        assertEquals(21L, getContentLength(emptyMap(), task(mapOf("Range" to "bytes=0-20"))))
        assertEquals(11L, getContentLength(emptyMap(), task(mapOf("range" to "bytes=10-20"))))
    }

    @Test
    fun openEndedRangeFallsThroughToKnownContentLength() {
        val t = task(mapOf("Range" to "bytes=10-", "Known-Content-Length" to "456"))
        assertEquals(456L, getContentLength(emptyMap(), t))
    }

    @Test
    fun contentLengthFromKnownContentLengthHeader() {
        assertEquals(456L, getContentLength(emptyMap(), task(mapOf("Known-Content-Length" to "456"))))
        assertEquals(456L, getContentLength(emptyMap(), task(mapOf("known-content-length" to "456"))))
    }

    @Test
    fun rangeHeaderTakesPrecedenceOverKnownContentLength() {
        val t = task(mapOf("Known-Content-Length" to "456", "Range" to "bytes=0-20"))
        assertEquals(21L, getContentLength(emptyMap(), t))
    }

    @Test
    fun contentLengthIsMinusOneWhenUndetermined() {
        assertEquals(-1L, getContentLength(emptyMap(), task()))
    }
}
