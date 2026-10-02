# Configuration

The downloader can be configured by calling `FileDownloader().configure` before executing any downloads or uploads. Configurations can be set for Global, Android, iOS or Desktop separately, where only the `globalConfig` is applied to every platform, before the platform-specific configuration is applied. This can be used to 'override' the configuration for only one platform.

Configurations are platform-specific and support and behavior may change between platforms. At this moment, consider configuration experimental, and expect changes that will not be considered breaking (and will not trigger a major version increase).

A configuration can be a single config or a list of configs, and every config is a `Record` with the first element a `String` indicating what to configure (use the `Config.` variables to avoid typos), and the second element an argument (which itself can be a `Record` if more than one argument is needed).

The following configurations are supported:
* Timeouts
  - `(Config.requestTimeout, Duration? duration)` sets the requestTimeout, or if null resets to default. This is the time allowed to connect with the server
  - `(Config.resourceTimeout, Duration? duration)` sets the iOS resourceTimeout, or if null resets to default. This is the time allowed to complete the download/upload
* Checking available space
  - `(Config.checkAvailableSpace, int minMegabytes)` ensures a file download fails if less than `minMegabytes` space will be available after this download completes
  - `(Config.checkAvailableSpace, false)` or `(Config.checkAvailableSpace, Config.never)` turns off checking available space
* Skipping download if destination file already present. Note the skip check is done at the moment the file is enqueued, not when it starts downloading.
  - `(Config.skipExistingFiles, true)` or `(Config.skipExistingFiles, Config.always)` skips download if the file is already present, and returns a `TaskStatusUpdate` with `TaskStatus.complete` and a 304 `responseStatusCode`
  - `(Config.skipExistingFiles, int minMegabytes)` only skips if the file exists *and* is greater than `minMegabytes` in size
  - `(Config.skipExistingFiles, false)` or `(Config.skipExistingFiles, Config.never)` is the default, and never skips file downloads
* Using a holding queue to limit the number of tasks running concurrently
  - `(Config.holdingQueue, (int? maxConcurrent, int? maxConcurrentByHost, int? maxConcurrentByGroup))` activates the holding queue and sets the constraints. Pass `null` for no constraint
  - `(Config.holdingQueue, false)` or `(Config.holdingQueue, Config.never)` deactivates the holding queue (make sure it is empty before deactivating)
  - Using the holding queue adds a queue on the native side where tasks may have to wait before being enqueued with the Android WorkManager or iOS URLSessions. Because the holding queue lives on the native side (not Dart) tasks will continue to get pulled from the holding queue even when the app is suspended by the OS. This is different from the `TaskQueue`, which lives on the Dart side and suspends when the app is suspended by the OS
  - When using a holding queue:
    - Tasks will be taken out of the queue based on their priority and time of creation, provided they pass the constraints imposed by the `maxConcurrent` values
    - Status messages will differ slightly. You will get the `TaskStatus.enqueued` update immediately upon enqueuing. Once the task gets enqueued with the Android WorkManager or iOS URLSessions you will not get another "enqueue" update, but if that enqueue fails the task will fail. Once the task starts running you will get `TaskStatus.running` as usual.
    - The holding queue and the native queues managed by the Android WorkManager or iOS URLSessions are treated as a single queue for queries like `taskForId` and `cancelTasksWithIds`. There is no way to determine whether a task is in the holding queue or already enqueued with the Android WorkManager or iOS URLSessions
* [Android] When to use the cache directory
  - `(Config.useCacheDir, String whenToUse)` with values 'never', 'always' or 'whenAble'. Default is `Config.whenAble`, which will use the cacheDir if the size of the file to download is less than half the cacheQuota given to your app by Android. If you find that your app fails to download large files or cannot resume from pause, set this to `Config.never` and make sure to clear up the directory aligned with `BaseDirectory.applicationSupport` for stray temp files. Temp file names start with `com.bbflight.background_downloader`. Note that the use of cache or applicationSupport directories responds to the configuration `Config.useExternalStorage`: if set, the external cache and applicationSupport directories will be used
* HTTP Proxy
  - `(Config.proxy, (String address, int port))` sets the proxy to this address and port (note: address and port are contained in a record)
  - `(Config.proxy, false)` removes the proxy
* [Android, Desktop] Bypassing HTTPS (TLS) certificate validation
  - `(Config.bypassTLSCertificateValidation, bool bypass)`  bypasses TLS certificate validation for HTTPS connections. This is insecure, and can not be used in release mode. It is meant to make it easier to use a local server with a self-signed certificate during development only. On Android, to turn the bypass off, restart your app with this configuration removed.
* [Android] run task in foreground (removes 9 minute timeout and may improve chances of task surviving background). 
  
  For a task to run in foreground it _must_ have a `running` notification configured, otherwise it will execute normally regardless of this setting. If targeting API 34 or greater, you must also add to your `AndroidManifest.xml` a permission declaration `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />` and the foreground service type definition (under the `application` element):
  ```
  <service
    android:name="androidx.work.impl.foreground.SystemForegroundService"
    android:foregroundServiceType="dataSync" />
  ```
  
  - `(Config.runInForeground, bool activate)` or `(Config.runInForeground, Config.always)` or `(Config.runInForeground, Config.never)` activates or de-activates foreground mode for all tasks.
  - `(Config.runInForegroundIfFileLargerThan, int fileSize)` activates foreground mode for downloads/uploads that exceed this file size, expressed in MB.
* [Android] Use external storage. 

  Either your app runs in default (internal storage) mode, or in external storage. You cannot switch between internal and external, as the directory structure that - for example - `BaseDirectory.applicationDocuments` refers to is different in each mode
  
  - `(Config.useExternalStorage, String whenToUse)` with values 'never' or 'always'. Default is `Config.never`. See [here](#android-external-storage) for important details
* [iOS] Localization
  - `(Config.localize, Map<String, String> translation)` localizes the words 'Cancel', 'Pause' and 'Resume' as used in notifications, presented as a map (iOS only, see docs for Android notifications)
* [iOS] Exclude downloaded file from iCloud backup
  - `(Config.excludeFromCloudBackup, bool exclude)` or `(Config.excludeFromCloudBackup, Config.always)` or `(Config.excludeFromCloudBackup, Config.never)` 

On Android and iOS, most configurations are stored in native 'shared preferences' to ensure that background tasks have access to the configuration. This means that configuration persists across application restarts, and this can lead to some surprising results. For example, if during testing you set a proxy and then remove that configuration line, the proxy configuration is not removed from persistent storage on your test device. You need to explicitly set `('proxy', false)` to remove the stored configuration on that device.

A configuration can be called multiple times, and affects all tasks *running* after the configuration call. Tasks enqueued _before_ a call, that run _after_ the call (e.g. because they are waiting for other downloads to complete) will run under the newly set configuration, not the one that was active when they were enqueued. On iOS, configuration of requestTimeout, resourceTimeout and proxy can only be set once, before the first task is executed

# Required metaData flags (DLCT fork)

[Android, iOS] An app can require that tasks in specific groups carry a flag in their `metaData` before they are allowed to run. This is a native declaration, not a `configure` call, because it must be enforced before any Dart code runs: on Android, WorkManager can start a previously enqueued task when the process starts, and on iOS, background `URLSession` tasks survive in the system daemon across app updates.

The declaration is a string of comma-separated `group=key` pairs, e.g. `mediaUploads=scrubbedUpload` or `mediaUploads=scrubbedUpload,documents=approved`. A task whose `group` is listed may run only if its `metaData` is a JSON object whose value for that group's `key` is the JSON boolean `true`. The string `"true"`, the number `1`, a missing key or `metaData` that is not a JSON object all count as missing. Tasks in unlisted groups, and all tasks in apps without a declaration, behave exactly as before.

Android: add to the `<application>` element of your `AndroidManifest.xml` (use `android:value`, not `android:resource`):
```xml
<meta-data
    android:name="com.bbflight.background_downloader.required_metadata_flags"
    android:value="mediaUploads=scrubbedUpload" />
```

iOS: add to your `Info.plist`:
```xml
<key>BDRequiredMetaDataFlags</key>
<string>mediaUploads=scrubbedUpload</string>
```

A task carrying the flag is created by putting it in `metaData`, e.g. `UploadTask(..., group: 'mediaUploads', metaData: jsonEncode({'scrubbedUpload': true}))`.

Enforcement:
* Android: every task is checked when it starts running, before the `beforeTaskStart` callback, any file access or any network request. This covers newly enqueued tasks, holding queue tasks, tasks rescheduled by WorkManager after a process restart, and UIDT tasks. A vetoed task ends with `TaskStatus.canceled` and is logged (task id and group) with `Log.w`.
* iOS: `enqueue` and `enqueueAll` return `false` for a vetoed task, before any file access, so it is never scheduled. When the background `URLSession` is created, every task in it is checked and vetoed tasks are canceled; such a task reports `TaskStatus.canceled`. If a declaration is present the session is created when the plugin registers at app launch, instead of on the first call from Dart. A task in the session whose stored task data cannot be decoded is canceled as well, because it cannot be shown to be outside a listed group.
* iOS, with a declaration: the session can report updates (including these cancellations, and tasks that finished while the app was not running) before any Dart code runs. Status, progress and resume data updates that arrive before Dart is ready are stored and delivered when the app calls `resumeFromBackground` (which `start` calls), the same way as updates for an app that was not running. Dart is ready once `FileDownloader` has finished initializing and the app has called `resumeFromBackground` or a method that uses the session, such as `enqueue`, `allTasks`, `taskForId` or `cancelTasksWithIds`; this is the moment the session would have been created without a declaration, so registering listeners and calling `trackTasks` before `start` (see [database](database.md)) still works as documented. Because the session is created before Dart can call `configure`, changes to the resource timeout, request timeout and proxy take effect from the next launch.
* A declaration that is present but malformed (an entry that is not exactly `group=key`, an empty group or key, a group listed twice, a value that is not a string, or no entries at all) makes the plugin veto every task and log an error, so the mistake is visible immediately instead of silently disabling the check. A missing or blank declaration means no flags are required.

Limits on iOS: a task that was already transferring in the system daemon before your app launched has done so outside the app's control; the check cancels it as soon as the app creates the session, but bytes already sent cannot be recalled.

# Android external storage

Android has a complex storage model, see [here](https://developer.android.com/training/data-storage), that allows you to store App-Specific files in internal or external storage, and also offers Shared Storage.  For Shared Storage you can use `FileDownloader().moveToSharedStorage` - this does not require configuration, and won't be covered here.

For App-specific storage you can configure the downloader to use either internal storage (the default) or external storage. Unlike other configurations, you cannot switch, so you have to choose which mode your app will use.

The configuration affects the path to the directories described by the `BaseDirectory` enum. For internal storage, the paths will look like this:
* BaseDirectory.applicationDocuments -> path is /data/user/0/com.bbflight.background_downloader_example/app_flutter/google.html
* BaseDirectory.applicationSupport -> path is /data/user/0/com.bbflight.background_downloader_example/files/google.html
* BaseDirectory.applicationLibrary -> path is /data/user/0/com.bbflight.background_downloader_example/files/Library/google.html
* BaseDirectory.temporary -> path is /data/user/0/com.bbflight.background_downloader_example/cache/google.html

Despite the somewhat strange `app_flutter` subdirectory, these paths line up with the directories you will get when using the `path_provider` package.

When configuring the downloader to use external storage, those same `BaseDirectory` entries will create a path like this:
* BaseDirectory.applicationDocuments -> path is /storage/emulated/0/Android/data/com.bbflight.background_downloader_example/files/google.html
* BaseDirectory.applicationSupport -> path is /storage/emulated/0/Android/data/com.bbflight.background_downloader_example/files/Support/google.html
* BaseDirectory.applicationLibrary -> path is /storage/emulated/0/Android/data/com.bbflight.background_downloader_example/files/Library/google.html
* BaseDirectory.temporary -> path is /storage/emulated/0/Android/data/com.bbflight.background_downloader_example/cache/google.html

Note the external `files` or `cache` directory is now a base, with subdirectories for 'Support' and 'Library'. Calls to `task.filePath` will return the correct path to these external directories - they cannot easily be constructed otherwise.

Never store absolute paths to these files, as the actual location may differ. Also note that using external storage can lead to errors, as the storage may not be available at the time it is requested. Therefore, `task.filePath` may throw a `FileSystemException` if using external storage. 
