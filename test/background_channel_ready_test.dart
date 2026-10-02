import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// [DLCT] iOS stores background channel updates locally until Dart confirms
/// its background handler with `backgroundChannelReady`, and counts an update
/// as delivered only if the handler replies with exactly `true`. These tests
/// pin the Dart half of that contract:
/// * the handshake is sent only after the handler is set,
/// * stored updates are popped only after the handshake completed,
/// * every message the handler handles is answered with `true`, and an
///   unknown message is not.

const methodChannel = MethodChannel('com.bbflight.background_downloader');
const backgroundChannelName = 'com.bbflight.background_downloader.background';
const backgroundChannel = MethodChannel(backgroundChannelName);
const codec = StandardMethodCodec();

final task = UploadTask(
  taskId: 'task',
  url: 'https://example.com/upload',
  filename: 'file.jpg',
  group: 'mediaUploads',
);

/// Sends [method] with [args] (after the task JSON) from the native side to
/// the Dart background handler and returns the decoded reply
Future<Object?> sendToDart(String method, List<Object?> args) async {
  final replyCompleter = Completer<Object?>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        backgroundChannelName,
        codec.encodeMethodCall(
          MethodCall(method, [jsonEncode(task.toJson()), ...args]),
        ),
        (ByteData? reply) {
          if (reply == null) {
            replyCompleter.complete(null);
            return;
          }
          try {
            replyCompleter.complete(codec.decodeEnvelope(reply));
          } on PlatformException catch (e) {
            replyCompleter.complete(e);
          }
        },
      );
  return replyCompleter.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final events = <String>[];
  final handshakeGate = Completer<void>();
  Object? replyDuringHandshake = 'no reply';
  late FileDownloader downloader;

  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      events.add(call.method);
      return switch (call.method) {
        'popResumeData' || 'popStatusUpdates' || 'popProgressUpdates' => '{}',
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(backgroundChannel, (call) async {
      if (call.method != 'backgroundChannelReady') {
        return null;
      }
      events.add('backgroundChannelReady');
      // the handler must already be set: a native post now gets `true`
      replyDuringHandshake = await sendToDart('statusUpdate', [
        TaskStatus.running.index,
      ]);
      await handshakeGate.future;
      return true;
    });
    downloader = FileDownloader(persistentStorage: _MemoryStore());
    await downloader.ready;
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockMethodCallHandler(backgroundChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('handshake follows the handler; pops follow the handshake', () async {
    final resumed = downloader.resumeFromBackground();
    await pumpEventQueue();
    expect(events, contains('backgroundChannelReady'));
    expect(replyDuringHandshake, isTrue);
    expect(
      events.where((method) => method.startsWith('pop')),
      isEmpty,
      reason: 'stored updates must not be popped before the handshake',
    );
    handshakeGate.complete();
    await resumed;
    final handshakeIndex = events.indexOf('backgroundChannelReady');
    for (final pop in [
      'popResumeData',
      'popStatusUpdates',
      'popProgressUpdates',
    ]) {
      expect(events.indexOf(pop), greaterThan(handshakeIndex), reason: pop);
    }
  });

  group('every handled message is answered with true', () {
    final messages = <String, (String, List<Object?>)>{
      'statusUpdate': ('statusUpdate', [TaskStatus.running.index]),
      'statusUpdate with response': (
        'statusUpdate',
        [
          TaskStatus.complete.index,
          'body',
          {'Content-Type': 'text/plain'},
          200,
          'text/plain',
          'utf-8',
        ],
      ),
      'statusUpdate with exception': (
        'statusUpdate',
        [
          TaskStatus.failed.index,
          'TaskConnectionException',
          'connection lost',
          -1,
          null,
        ],
      ),
      'progressUpdate': ('progressUpdate', [0.5, 100, 1.0, 1000]),
      'canResume': ('canResume', [true]),
      'resumeData (iOS)': ('resumeData', ['data']),
      'resumeData (Android)': ('resumeData', ['data', 10, 'etag']),
      'notificationTap': (
        'notificationTap',
        [NotificationType.complete.index],
      ),
    };
    for (final MapEntry(key: name, value: (method, args))
        in messages.entries) {
      test(name, () async {
        expect(await sendToDart(method, args), isTrue);
      });
    }

    test('an unknown message is not answered with true', () async {
      final reply = await sendToDart('noSuchMessage', ['x']);
      expect(reply, isA<PlatformException>());
    });
  });
}

/// Empty, working persistent storage
class _MemoryStore implements PersistentStorage {
  final _resumeData = <String, ResumeData>{};
  final _pausedTasks = <String, Task>{};

  @override
  Future<void> initialize() async {}

  @override
  (String, int) get currentDatabaseVersion => ('MemoryStore', 1);

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
  Future<void> storePausedTask(Task task) async =>
      _pausedTasks[task.taskId] = task;

  @override
  Future<Task?> retrievePausedTask(String taskId) async =>
      _pausedTasks[taskId];

  @override
  Future<List<Task>> retrieveAllPausedTasks() async =>
      _pausedTasks.values.toList();

  @override
  Future<void> removePausedTask(String? taskId) async => taskId == null
      ? _pausedTasks.clear()
      : _pausedTasks.remove(taskId);

  @override
  Future<void> storeResumeData(ResumeData resumeData) async =>
      _resumeData[resumeData.taskId] = resumeData;

  @override
  Future<ResumeData?> retrieveResumeData(String taskId) async =>
      _resumeData[taskId];

  @override
  Future<List<ResumeData>> retrieveAllResumeData() async =>
      _resumeData.values.toList();

  @override
  Future<void> removeResumeData(String? taskId) async => taskId == null
      ? _resumeData.clear()
      : _resumeData.remove(taskId);
}
