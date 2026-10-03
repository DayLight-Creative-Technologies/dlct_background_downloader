//
//  PluginSymbols.swift
//  RequiredMetaDataFlagsTests
//
//  [DLCT] Stand-ins for the plugin symbols that RequiredMetaDataFlags.swift
//  references but that live in plugin files which import Flutter. They carry
//  no veto logic: the parser and decision under test are compiled from the
//  plugin's own RequiredMetaDataFlags.swift (symlinked next to this file).
//

import Foundation
import os.log

/// Stand-in for the plugin's `log` (BDPlugin.swift)
let log = OSLog(subsystem: "BackgroundDownloaderTests", category: "RequiredMetaDataFlags")

/// Stand-in for the plugin's `Task` (Task.swift), reduced to the fields the
/// veto file reads
struct Task {
    var taskId: String
    var group: String
    var metaData: String
}

/// Stand-in for the plugin's `getTaskFrom(urlSessionTask:)` (TaskFunctions.swift)
func getTaskFrom(urlSessionTask: URLSessionTask) -> Task? {
    return nil
}
