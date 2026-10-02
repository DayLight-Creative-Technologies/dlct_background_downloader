package com.bbflight.background_downloader

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * [DLCT] App-declared "required metaData flag" veto.
 *
 * A host app may declare, per task group, a key that must be present in the
 * task's [Task.metaData] JSON object with the boolean value `true` for the task
 * to be allowed to run. Tasks in a listed group that lack the flag are vetoed
 * (they end with [TaskStatus.canceled] before any file access or network
 * request). Tasks in unlisted groups, and all tasks in apps that do not declare
 * anything, are unaffected.
 *
 * Declaration format: comma-separated `group=key` pairs, e.g.
 * `mediaUploads=scrubbedUpload,otherGroup=otherKey`. Whitespace around groups,
 * keys and pairs is ignored, as are empty segments (e.g. a trailing comma).
 *
 * On Android the declaration is read from the host app's AndroidManifest
 * `<application>` meta-data named [MANIFEST_KEY].
 *
 * A declaration that is present but malformed is [Malformed]: the plugin can no
 * longer tell which groups the app meant to protect, so it fails closed and
 * vetoes every task, logging the reason. A misconfigured declaration therefore
 * surfaces immediately (every transfer is canceled) instead of silently dropping
 * the guarantee.
 */
sealed class RequiredMetaDataFlags {

    /** No declaration: every task runs unchanged */
    data object None : RequiredMetaDataFlags()

    /** Valid declaration: [keyByGroup] maps each protected group to its required key */
    data class Declared(val keyByGroup: Map<String, String>) : RequiredMetaDataFlags()

    /** Declaration present but unusable; every task is vetoed */
    data class Malformed(val reason: String) : RequiredMetaDataFlags()

    companion object {
        const val MANIFEST_KEY = "com.bbflight.background_downloader.required_metadata_flags"

        @Volatile
        private var manifestFlags: RequiredMetaDataFlags? = null

        /**
         * Parses a declaration string. Pure.
         *
         * Returns [None] for a null or blank [declaration], [Declared] for a valid
         * one and [Malformed] (with the reason) otherwise. A declaration is
         * malformed if any non-empty entry is not exactly `group=key` with a
         * non-empty group and key, if a group is listed more than once, or if it
         * contains no entries at all.
         */
        fun parse(declaration: String?): RequiredMetaDataFlags {
            if (declaration == null || declaration.isBlank()) {
                return None
            }
            val keyByGroup = LinkedHashMap<String, String>()
            for (rawEntry in declaration.split(',')) {
                val entry = rawEntry.trim()
                if (entry.isEmpty()) {
                    continue
                }
                val parts = entry.split('=')
                if (parts.size != 2) {
                    return Malformed("entry '$entry' is not of the form group=key")
                }
                val group = parts[0].trim()
                val key = parts[1].trim()
                if (group.isEmpty() || key.isEmpty()) {
                    return Malformed("entry '$entry' has an empty group or key")
                }
                if (keyByGroup.containsKey(group)) {
                    return Malformed("group '$group' is listed more than once")
                }
                keyByGroup[group] = key
            }
            if (keyByGroup.isEmpty()) {
                return Malformed("declaration contains no group=key entries")
            }
            return Declared(keyByGroup)
        }

        /**
         * Returns true if a task in [group] with [metaData] must not run. Pure.
         *
         * - [None]: never vetoed
         * - [Malformed]: always vetoed (fail closed)
         * - [Declared]: vetoed only if [group] is listed and [metaData] does not
         *   parse as a JSON object whose value for the group's key is the JSON
         *   boolean `true` (the string `"true"`, the number `1` and any other
         *   value do not count)
         */
        fun isVetoed(group: String, metaData: String, flags: RequiredMetaDataFlags): Boolean {
            return when (flags) {
                is None -> false
                is Malformed -> true
                is Declared -> {
                    val key = flags.keyByGroup[group] ?: return false
                    !hasTrueFlag(metaData, key)
                }
            }
        }

        /** True if [metaData] is a JSON object whose [key] holds the JSON boolean `true` */
        private fun hasTrueFlag(metaData: String, key: String): Boolean {
            val element = try {
                Json.parseToJsonElement(metaData)
            } catch (e: SerializationException) {
                return false
            }
            val value = (element as? JsonObject)?.get(key) as? JsonPrimitive ?: return false
            return !value.isString && value.booleanOrNull == true
        }

        /**
         * Returns the flags declared in the host app's manifest.
         *
         * The manifest cannot change while the process is alive (an app update
         * restarts the process), so the result is computed once per process. A
         * failure to read the app's own manifest fails closed ([Malformed]).
         */
        fun fromManifest(context: Context): RequiredMetaDataFlags {
            manifestFlags?.let { return it }
            val flags = readManifest(context)
            if (flags is Malformed) {
                Log.e(
                    TaskRunner.TAG,
                    "Meta-data $MANIFEST_KEY is malformed (${flags.reason}): every task will be canceled until it is fixed"
                )
            }
            manifestFlags = flags
            return flags
        }

        private fun readManifest(context: Context): RequiredMetaDataFlags {
            val applicationInfo: ApplicationInfo = try {
                val packageManager = context.packageManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.getApplicationInfo(
                        context.packageName,
                        PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong())
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
                }
            } catch (e: PackageManager.NameNotFoundException) {
                return Malformed("could not read the app's own manifest: $e")
            }
            val metaData = applicationInfo.metaData ?: return None
            if (!metaData.containsKey(MANIFEST_KEY)) {
                return None
            }
            val declaration = metaData.getString(MANIFEST_KEY)
                ?: return Malformed("value is not a string (use android:value, not android:resource)")
            return parse(declaration)
        }
    }
}
