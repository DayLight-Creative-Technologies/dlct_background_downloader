import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

/// [DLCT] A failing paused-task store must not prevent the platform query or
/// cancellation in allTasks, cancelTasksWithIds, taskForId and reset.

/// Error as forwarded by [LocalStorePersistentStorage] from its background
/// isolate: the stringified exception, not the exception object
const pausedStoreError =
    "PathAccessException: Cannot open file, path = '/var/mobile/Containers/"
    "Data/Application/X/Library/Application Support/backgroundDownloaderPausedTasks' "
    '(OS Error: Operation not permitted, errno = 1)';

final nativeTask = UploadTask(
  taskId: 'nativeTask',
  url: 'https://example.com/upload',
  filename: 'file.jpg',
  group: 'mediaUploads',
);

const channel = MethodChannel('com.bbflight.background_downloader');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final nativeCalls = <MethodCall>[];
  final warnings = <LogRecord>[];
  late FileDownloader downloader;

  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          return switch (call.method) {
            'allTasks' => [jsonEncode(nativeTask.toJson())],
            'cancelTasksWithIds' => true,
            'taskForId' => jsonEncode(nativeTask.toJson()),
            'reset' => 3,
            _ => null,
          };
        });
    Logger.root.onRecord
        .where((record) => record.level == Level.WARNING)
        .listen(warnings.add);
    downloader = FileDownloader(persistentStorage: _FailingPausedStore());
    await downloader.ready;
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() {
    nativeCalls.clear();
    warnings.clear();
  });

  bool warnedFor(String operation) => warnings.any(
    (record) =>
        record.message.contains('Could not read paused tasks during $operation') &&
        record.error == pausedStoreError,
  );

  test('getPausedTasks itself still surfaces the store failure', () async {
    await expectLater(
      downloader.downloaderForTesting.getPausedTasks(),
      throwsA(pausedStoreError),
    );
  });

  test('allTasks still queries the platform', () async {
    final tasks = await downloader.allTasks(group: 'mediaUploads');
    expect(nativeCalls.map((call) => call.method), contains('allTasks'));
    expect(tasks.map((task) => task.taskId), equals(['nativeTask']));
    expect(warnedFor('allTasks'), isTrue);
  });

  test('cancelTasksWithIds still cancels on the platform', () async {
    final result = await downloader.cancelTasksWithIds(['nativeTask']);
    expect(result, isTrue);
    final cancelCall = nativeCalls.singleWhere(
      (call) => call.method == 'cancelTasksWithIds',
    );
    expect(cancelCall.arguments, equals(['nativeTask']));
    expect(warnedFor('cancelTasksWithIds'), isTrue);
  });

  test('taskForId still queries the platform', () async {
    final task = await downloader.taskForId('nativeTask');
    expect(nativeCalls.map((call) => call.method), contains('taskForId'));
    expect(task?.taskId, equals('nativeTask'));
    expect(warnedFor('taskForId'), isTrue);
  });

  test('reset still resets on the platform', () async {
    final count = await downloader.reset(group: 'mediaUploads');
    final resetCall = nativeCalls.singleWhere((call) => call.method == 'reset');
    expect(resetCall.arguments, equals('mediaUploads'));
    expect(count, equals(3));
    expect(warnedFor('reset'), isTrue);
  });
}

/// Persistent storage whose paused-task store fails the way
/// [LocalStorePersistentStorage] does after an iOS file-permission error;
/// everything else is empty
class _FailingPausedStore implements PersistentStorage {
  @override
  Future<List<Task>> retrieveAllPausedTasks() => Future.error(pausedStoreError);

  @override
  Future<void> initialize() async {}

  @override
  (String, int) get currentDatabaseVersion => ('FailingPausedStore', 1);

  @override
  Future<(String, int)> get storedDatabaseVersion async =>
      currentDatabaseVersion;

  @override
  Future<void> storeTaskRecord(TaskRecord record) async {}

  @override
  Future<TaskRecord?> retrieveTaskRecord(String taskId) async => null;

  @override
  Future<List<TaskRecord>> retrieveAllTaskRecords() async => [];

  @override
  Future<void> removeTaskRecord(String? taskId) async {}

  @override
  Future<void> storePausedTask(Task task) async {}

  @override
  Future<Task?> retrievePausedTask(String taskId) async => null;

  @override
  Future<void> removePausedTask(String? taskId) async {}

  @override
  Future<void> storeResumeData(ResumeData resumeData) async {}

  @override
  Future<ResumeData?> retrieveResumeData(String taskId) async => null;

  @override
  Future<List<ResumeData>> retrieveAllResumeData() async => [];

  @override
  Future<void> removeResumeData(String? taskId) async {}
}
