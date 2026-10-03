//
//  RequiredMetaDataFlags.swift
//  background_downloader
//
//  [DLCT] App-declared "required metaData flag" veto.
//

import Foundation
import os.log

/// App-declared "required metaData flag" veto.
///
/// A host app may declare, per task group, a key that must be present in the
/// task's `metaData` JSON object with the boolean value `true` for the task to
/// be allowed to run. Tasks in a listed group that lack the flag are refused at
/// enqueue and canceled when the background `URLSession` is (re)created. Tasks
/// in unlisted groups, and all tasks in apps that do not declare anything, are
/// unaffected.
///
/// Declaration format: comma-separated `group=key` pairs, e.g.
/// `mediaUploads=scrubbedUpload,otherGroup=otherKey`. Whitespace around groups,
/// keys and pairs is ignored, as are empty segments (e.g. a trailing comma).
///
/// On iOS the declaration is the String value of Info.plist key
/// `BDRequiredMetaDataFlags`.
///
/// A declaration that is present but malformed is `.malformed`: the plugin can
/// no longer tell which groups the app meant to protect, so it fails closed and
/// vetoes every task, logging the reason. A misconfigured declaration therefore
/// surfaces immediately instead of silently dropping the guarantee.
enum RequiredMetaDataFlags: Equatable, Sendable {
    /// No declaration: every task runs unchanged
    case none
    /// Valid declaration: maps each protected group to its required key
    case declared([String: String])
    /// Declaration present but unusable (with the reason); every task is vetoed
    case malformed(String)

    static let infoPlistKey = "BDRequiredMetaDataFlags"

    /// The flags declared in the host app's Info.plist, computed once per process
    /// (the Info.plist cannot change while the process is alive)
    static let fromInfoPlist: RequiredMetaDataFlags = {
        let flags = fromInfoPlistValue(Bundle.main.object(forInfoDictionaryKey: infoPlistKey))
        if case .malformed(let reason) = flags {
            os_log("Info.plist key %@ is malformed (%@): every task will be canceled until it is fixed", log: log, type: .error, infoPlistKey, reason)
        }
        return flags
    }()

    /// The flags for the Info.plist value of `infoPlistKey`. Pure.
    ///
    /// - absent (`nil`): `.none`
    /// - present but not a String: `.malformed` (fail closed)
    /// - present String: `parse`d
    static func fromInfoPlistValue(_ rawValue: Any?) -> RequiredMetaDataFlags {
        guard let rawValue = rawValue else {
            return .none
        }
        guard let declaration = rawValue as? String else {
            return .malformed("value is not a String")
        }
        return parse(declaration)
    }

    /// Parses a declaration string. Pure.
    ///
    /// Returns `.none` for a nil or blank `declaration`, `.declared` for a valid
    /// one and `.malformed` (with the reason) otherwise. A declaration is
    /// malformed if any non-empty entry is not exactly `group=key` with a
    /// non-empty group and key, if a group is listed more than once, or if it
    /// contains no entries at all.
    static func parse(_ declaration: String?) -> RequiredMetaDataFlags {
        guard let declaration = declaration,
              !declaration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .none
        }
        var keyByGroup = [String: String]()
        for rawEntry in declaration.split(separator: ",", omittingEmptySubsequences: false) {
            let entry = rawEntry.trimmingCharacters(in: .whitespacesAndNewlines)
            if entry.isEmpty {
                continue
            }
            let parts = entry.split(separator: "=", omittingEmptySubsequences: false)
            if parts.count != 2 {
                return .malformed("entry '\(entry)' is not of the form group=key")
            }
            let group = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let key = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if group.isEmpty || key.isEmpty {
                return .malformed("entry '\(entry)' has an empty group or key")
            }
            if keyByGroup[group] != nil {
                return .malformed("group '\(group)' is listed more than once")
            }
            keyByGroup[group] = key
        }
        if keyByGroup.isEmpty {
            return .malformed("declaration contains no group=key entries")
        }
        return .declared(keyByGroup)
    }

    /// Returns true if a task in `group` with `metaData` must not run. Pure.
    ///
    /// - `.none`: never vetoed
    /// - `.malformed`: always vetoed (fail closed)
    /// - `.declared`: vetoed only if `group` is listed and `metaData` does not
    ///   parse as a JSON object whose value for the group's key is the JSON
    ///   boolean `true` (the string `"true"`, the number `1` and any other value
    ///   do not count)
    static func isVetoed(group: String, metaData: String, flags: RequiredMetaDataFlags) -> Bool {
        switch flags {
        case .none:
            return false
        case .malformed:
            return true
        case .declared(let keyByGroup):
            guard let key = keyByGroup[group] else {
                return false
            }
            return !hasTrueFlag(metaData: metaData, key: key)
        }
    }

    /// Returns true if `task` must not run under `flags`: the decision
    /// `doEnqueue` takes for every task. Pure.
    ///
    /// The task's own group and metaData are what `isVetoed` judges.
    static func isTaskVetoed(_ task: Task, flags: RequiredMetaDataFlags) -> Bool {
        return isVetoed(group: task.group, metaData: task.metaData, flags: flags)
    }

    /// Returns true if the URLSession task whose stored Task decodes to `task`
    /// must be canceled when the background session is (re)created under
    /// `flags`. Pure.
    ///
    /// - `.none`: nothing is canceled
    /// - a stored Task that could not be decoded (`nil`): canceled, because it
    ///   cannot be shown to be outside a protected group
    /// - otherwise: canceled if `isTaskVetoed`
    static func cancelsAtSessionCreation(_ task: Task?, flags: RequiredMetaDataFlags) -> Bool {
        if flags == .none {
            return false
        }
        guard let task = task else {
            return true
        }
        return isTaskVetoed(task, flags: flags)
    }

    /// True if `metaData` is a JSON object whose `key` holds the JSON boolean `true`
    private static func hasTrueFlag(metaData: String, key: String) -> Bool {
        guard let data = metaData.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let number = object[key] as? NSNumber
        else {
            return false
        }
        // JSON booleans decode as CFBoolean; a JSON number 1 is also an NSNumber
        // whose boolValue is true, so the type must be checked explicitly
        return CFGetTypeID(number) == CFBooleanGetTypeID() && number.boolValue
    }
}

/// Returns true, and logs, if `task` must not be enqueued because the app
/// declared a required metaData flag for its group that the task lacks
func isVetoedByRequiredMetaDataFlag(task: Task) -> Bool {
    if RequiredMetaDataFlags.isTaskVetoed(task, flags: RequiredMetaDataFlags.fromInfoPlist) {
        os_log("TaskId %@ in group %@ refused: required metaData flag missing", log: log, type: .error, task.taskId, task.group)
        return true
    }
    return false
}

/// Cancels every task in `session` that the app's required metaData flags veto.
///
/// Called when the background `URLSession` is (re)created, which reconnects the
/// app to tasks that survived in nsurlsessiond (e.g. across an app update). A
/// canceled task reports `.canceled` through the session delegate. A task whose
/// stored Task JSON cannot be decoded cannot be shown to be outside a protected
/// group, so it is canceled too (the session delegate cannot process such a task
/// anyway). No-op when the app declares no flags.
func cancelTasksVetoedByRequiredMetaDataFlags(in session: URLSession) {
    let flags = RequiredMetaDataFlags.fromInfoPlist
    if flags == .none {
        return
    }
    session.getAllTasks { urlSessionTasks in
        for urlSessionTask in urlSessionTasks {
            let task = getTaskFrom(urlSessionTask: urlSessionTask)
            if !RequiredMetaDataFlags.cancelsAtSessionCreation(task, flags: flags) {
                continue
            }
            if let task = task {
                os_log("TaskId %@ in group %@ canceled: required metaData flag missing", log: log, type: .error, task.taskId, task.group)
            } else {
                os_log("URLSessionTask %d canceled: stored task could not be decoded to check required metaData flags", log: log, type: .error, urlSessionTask.taskIdentifier)
            }
            urlSessionTask.cancel()
        }
    }
}
