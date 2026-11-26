import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

final persistenceFailures = ValueNotifier<Set<String>>({});
final restoredDataAwaitingRestart = ValueNotifier<bool>(false);
List<Future<void> Function()> persistenceFlushers = [];
final restoredFilePaths = <String>{};

dynamic _decodeJsonObject(String raw) {
  final value = jsonDecode(raw);
  if (value is! Map) throw const FormatException('Expected a JSON object');
  return value;
}

Future<void> flushPersistentStores() =>
    Future.wait(persistenceFlushers.map((flush) => flush()));

/// Per-store ordered writes. A failed write does not poison later retries.
mixin ReliablePersistence {
  Future<void> _pendingWrite = Future.value();
  bool _loadFailed = false;
  Object? lastPersistenceError;

  Future<dynamic> readJson(
    File file, {
    int isolateThresholdBytes = 32768,
  }) async {
    try {
      final raw = await file.readAsString();
      final value = raw.length > isolateThresholdBytes
          ? await compute(_decodeJsonObject, raw)
          : _decodeJsonObject(raw);
      _loadFailed = false;
      return value;
    } catch (error) {
      _loadFailed = true;
      _failure(file, error);
      rethrow;
    }
  }

  void _failure(File file, Object error) {
    lastPersistenceError = error;
    persistenceFailures.value = {...persistenceFailures.value, file.path};
  }

  Future<void> writeJson(
    File file,
    String snapshot, {
    Future<void> Function()? beforeWrite,
  }) {
    final operation = _pendingWrite.then((_) async {
      // Restore writes a new on-disk state. Stale in-memory objects must not overwrite it before restart.
      if (restoredFilePaths.contains(file.path)) return;
      try {
        if (_loadFailed) {
          throw StateError(
            'Existing data could not be read; refusing to overwrite',
          );
        }
        await beforeWrite?.call();
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(snapshot, flush: true);
        await temporary.rename(file.path);
        lastPersistenceError = null;
        persistenceFailures.value = {...persistenceFailures.value}
          ..remove(file.path);
      } catch (error) {
        _failure(file, error);
        rethrow;
      }
    });
    _pendingWrite = operation.catchError((Object _) {});
    return operation;
  }
}
