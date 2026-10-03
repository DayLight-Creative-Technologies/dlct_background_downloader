// swift-tools-version: 5.9

// [DLCT] Test-only package for the required-metaData-flag veto
// (`RequiredMetaDataFlags.swift`). Not part of the plugin: neither the podspec
// nor `ios/background_downloader/Package.swift` refers to it.
//
// `Sources/RequiredMetaDataFlagsCore/RequiredMetaDataFlags.swift` is a symlink
// to the plugin's own source file, so `swift test` compiles exactly the code
// the plugin ships. The plugin target itself cannot be built here because the
// rest of its sources import Flutter; `PluginSymbols.swift` supplies the three
// plugin symbols the veto file references (`log`, `Task`, `getTaskFrom`).
//
// Run with `swift test` from this directory (macOS). CI: the `Native veto
// tests (iOS)` job in `.github/workflows/build.yml`.

import PackageDescription

let package = Package(
    name: "RequiredMetaDataFlagsTests",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .target(
            name: "RequiredMetaDataFlagsCore",
            path: "Sources/RequiredMetaDataFlagsCore"
        ),
        .testTarget(
            name: "RequiredMetaDataFlagsCoreTests",
            dependencies: ["RequiredMetaDataFlagsCore"],
            path: "Tests/RequiredMetaDataFlagsCoreTests"
        ),
    ]
)
