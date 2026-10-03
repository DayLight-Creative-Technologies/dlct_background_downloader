package com.bbflight.background_downloader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RequiredMetaDataFlagsTest {

    private val declared = RequiredMetaDataFlags.parse("mediaUploads=scrubbed")
    private val twoGroups = RequiredMetaDataFlags.parse("mediaUploads=scrubbed,avatars=resized")

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
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"scrubbed":1.0}""", declared))
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

    @Test
    fun `every declared group requires its own key`() {
        assertFalse(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"scrubbed":true}""", twoGroups))
        assertFalse(RequiredMetaDataFlags.isVetoed("avatars", """{"resized":true}""", twoGroups))
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", "{}", twoGroups))
        assertTrue(RequiredMetaDataFlags.isVetoed("avatars", "{}", twoGroups))
        assertTrue(RequiredMetaDataFlags.isVetoed("avatars", """{"resized":false}""", twoGroups))
    }

    @Test
    fun `another group's key does not satisfy the flag`() {
        assertTrue(RequiredMetaDataFlags.isVetoed("mediaUploads", """{"resized":true}""", twoGroups))
        assertTrue(RequiredMetaDataFlags.isVetoed("avatars", """{"scrubbed":true}""", twoGroups))
        assertFalse(RequiredMetaDataFlags.isVetoed("default", "", twoGroups))
    }

    // fromDeclaration: the manifest meta-data as readManifest hands it over

    @Test
    fun `absent manifest meta-data is None and its value is never read`() {
        var read = false
        assertEquals(RequiredMetaDataFlags.None, RequiredMetaDataFlags.fromDeclaration(false) { read = true; "mediaUploads=scrubbed" })
        assertFalse(read)
    }

    @Test
    fun `manifest meta-data that is not a String fails closed`() {
        val flags = RequiredMetaDataFlags.fromDeclaration(true) { null }
        assertTrue(flags is RequiredMetaDataFlags.Malformed)
        assertTrue(RequiredMetaDataFlags.isVetoed("default", """{"scrubbed":true}""", flags))
    }

    @Test
    fun `manifest meta-data String is parsed`() {
        assertEquals(declared, RequiredMetaDataFlags.fromDeclaration(true) { "mediaUploads=scrubbed" })
        assertTrue(RequiredMetaDataFlags.fromDeclaration(true) { "mediaUploads" } is RequiredMetaDataFlags.Malformed)
        assertEquals(RequiredMetaDataFlags.None, RequiredMetaDataFlags.fromDeclaration(true) { " " })
    }

    // isTaskVetoed: the decision TaskRunner.run takes for a real Task

    private fun task(group: String, metaData: String, taskId: String = "veto-test") = Task(
        taskId = taskId,
        url = "https://example.com/upload",
        filename = "x.webp",
        headers = emptyMap(),
        baseDirectory = BaseDirectory.applicationDocuments,
        group = group,
        updates = Updates.status,
        metaData = metaData,
        taskType = "UploadTask"
    )

    @Test
    fun `a manifest declaring the group vetoes an unmarked task and runs a marked one`() {
        val flags = RequiredMetaDataFlags.fromDeclaration(true) { "mediaUploads=scrubbed" }
        assertTrue(RequiredMetaDataFlags.isTaskVetoed(task("mediaUploads", """{"uuid":"u1"}"""), flags))
        assertTrue(RequiredMetaDataFlags.isTaskVetoed(task("mediaUploads", ""), flags))
        assertFalse(RequiredMetaDataFlags.isTaskVetoed(task("mediaUploads", """{"uuid":"u1","scrubbed":true}"""), flags))
        assertFalse(RequiredMetaDataFlags.isTaskVetoed(task("default", ""), flags))
    }

    @Test
    fun `the task's own group and metaData decide, not its id`() {
        val flags = RequiredMetaDataFlags.fromDeclaration(true) { "mediaUploads=scrubbed" }
        assertTrue(RequiredMetaDataFlags.isTaskVetoed(task("mediaUploads", "{}", taskId = "default"), flags))
        assertFalse(RequiredMetaDataFlags.isTaskVetoed(task("default", "{}", taskId = "mediaUploads"), flags))
        assertFalse(
            RequiredMetaDataFlags.isTaskVetoed(task("mediaUploads", """{"scrubbed":true}""", taskId = """{}"""), flags)
        )
    }

    @Test
    fun `no manifest declaration runs every task, a non-String one vetoes every task`() {
        val none = RequiredMetaDataFlags.fromDeclaration(false) { null }
        assertFalse(RequiredMetaDataFlags.isTaskVetoed(task("mediaUploads", ""), none))
        val notString = RequiredMetaDataFlags.fromDeclaration(true) { null }
        assertTrue(RequiredMetaDataFlags.isTaskVetoed(task("default", """{"scrubbed":true}"""), notString))
    }
}
