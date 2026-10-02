package com.bbflight.background_downloader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RequiredMetaDataFlagsTest {

    private val declared = RequiredMetaDataFlags.parse("mediaUploads=scrubbed")

    // parse

    @Test
    fun `null or blank declaration is None`() {
        assertEquals(RequiredMetaDataFlags.None, RequiredMetaDataFlags.parse(null))
        assertEquals(RequiredMetaDataFlags.None, RequiredMetaDataFlags.parse(""))
        assertEquals(RequiredMetaDataFlags.None, RequiredMetaDataFlags.parse("   "))
    }

    @Test
    fun `single pair is parsed`() {
        assertEquals(
            RequiredMetaDataFlags.Declared(mapOf("mediaUploads" to "scrubbed")),
            declared
        )
    }

    @Test
    fun `multiple pairs with whitespace and empty segments are parsed`() {
        assertEquals(
            RequiredMetaDataFlags.Declared(mapOf("a" to "k1", "b" to "k2")),
            RequiredMetaDataFlags.parse(" a = k1 , ,b=k2, ")
        )
    }

    @Test
    fun `entry without equals sign is malformed`() {
        assertTrue(RequiredMetaDataFlags.parse("mediaUploads") is RequiredMetaDataFlags.Malformed)
        assertTrue(RequiredMetaDataFlags.parse("a=k1,b") is RequiredMetaDataFlags.Malformed)
    }

    @Test
    fun `entry with more than one equals sign is malformed`() {
        assertTrue(RequiredMetaDataFlags.parse("a=k=v") is RequiredMetaDataFlags.Malformed)
    }

    @Test
    fun `entry with empty group or key is malformed`() {
        assertTrue(RequiredMetaDataFlags.parse("=k") is RequiredMetaDataFlags.Malformed)
        assertTrue(RequiredMetaDataFlags.parse("a=") is RequiredMetaDataFlags.Malformed)
        assertTrue(RequiredMetaDataFlags.parse(" = ") is RequiredMetaDataFlags.Malformed)
    }

    @Test
    fun `group listed twice is malformed`() {
        assertTrue(RequiredMetaDataFlags.parse("a=k1,a=k2") is RequiredMetaDataFlags.Malformed)
        assertTrue(RequiredMetaDataFlags.parse("a=k1,a=k1") is RequiredMetaDataFlags.Malformed)
    }

    @Test
    fun `declaration with only separators is malformed`() {
        assertTrue(RequiredMetaDataFlags.parse(",") is RequiredMetaDataFlags.Malformed)
        assertTrue(RequiredMetaDataFlags.parse(" , , ") is RequiredMetaDataFlags.Malformed)
    }

    // isVetoed

    @Test
    fun `no declaration never vetoes`() {
        assertFalse(RequiredMetaDataFlags.isVetoed("mediaUploads", "", RequiredMetaDataFlags.None))
        assertFalse(RequiredMetaDataFlags.isVetoed("mediaUploads", "not json", RequiredMetaDataFlags.None))
    }

    @Test
    fun `malformed declaration vetoes every task`() {
        val malformed = RequiredMetaDataFlags.parse("mediaUploads")
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"scrubbed":true}""", malformed))
        assertTrue(RequiredMetaDataFlags.isVetoed("default", "", malformed))
    }

    @Test
    fun `unlisted group is never vetoed`() {
        assertFalse(RequiredMetaDataFlags.isVetoed("default", "", declared))
        assertFalse(RequiredMetaDataFlags.isVetoed("default", """{"scrubbed":false}""", declared))
    }

    @Test
    fun `listed group with boolean true flag runs`() {
        assertFalse(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"scrubbed":true}""", declared))
        assertFalse(
            RequiredMetaDataFlags.isVetoed(
                "mediaUploads",
                """{"other":1,"scrubbed": true,"nested":{"x":[1,2]}}""",
                declared
            )
        )
    }

    @Test
    fun `listed group without the flag is vetoed`() {
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", "", declared))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", "{}", declared))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"other":true}""", declared))
    }

    @Test
    fun `listed group with a non-boolean-true flag value is vetoed`() {
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"scrubbed":false}""", declared))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"scrubbed":"true"}""", declared))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"scrubbed":1}""", declared))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"scrubbed":null}""", declared))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"scrubbed":[true]}""", declared))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"scrubbed":{"v":true}}""", declared))
    }

    @Test
    fun `listed group with metaData that is not a JSON object is vetoed`() {
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", "not json", declared))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", "true", declared))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """[{"scrubbed":true}]""", declared))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """"scrubbed"""", declared))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"scrubbed":true""", declared))
    }

    @Test
    fun `flag key match is case sensitive`() {
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"Scrubbed":true}""", declared))
        assertFalse(RequiredMetaDataFlags.isVetoed("MediaUploads", "", declared))
    }
}
