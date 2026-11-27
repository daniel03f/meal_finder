import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class PerformanceRecorder {
  final Map<String, List<int>> _stageDurationsMs = {};
  final List<double> _fpsValues = [];
  DateTime? _runStartedAt;

  PerformanceRecorder() {
    for (final stage in [
      'detection',
      'classification',
      'crop',
      'preprocessing',
      'embedding',
      'database',
      'guidance',
    ]) {
      _stageDurationsMs[stage] = [];
    }
  }

  void startRun({DateTime? startedAt}) {
    _runStartedAt = startedAt ?? DateTime.now();
    _fpsValues.clear();
    for (final stage in _stageDurationsMs.keys) {
      _stageDurationsMs[stage]!.clear();
    }
  }

  void recordStage(String stage, Duration duration) {
    _stageDurationsMs.putIfAbsent(stage, () => []).add(duration.inMilliseconds);
  }

  void recordFps(double fps) {
    _fpsValues.add(fps);
  }

  Future<String> finishRun({required Map<String, dynamic> config}) async {
    final startedAt = _runStartedAt ?? DateTime.now();
    final finishedAt = DateTime.now();

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/benchmark_results.json');

    final summary = {
      'timestamp': startedAt.toIso8601String(),
      'config': config,
      'totalLatencyMs': finishedAt.difference(startedAt).inMilliseconds,
      'fpsMean': _fpsValues.isEmpty ? 0.0 : _fpsValues.reduce((a, b) => a + b) / _fpsValues.length,
      'stages': {
        for (final entry in _stageDurationsMs.entries)
          entry.key: {
            'meanMs': entry.value.isEmpty
                ? 0
                : entry.value.reduce((a, b) => a + b) / entry.value.length,
            'samplesMs': entry.value,
            'totalMs': entry.value.isEmpty ? 0 : entry.value.reduce((a, b) => a + b),
          }
      },
    };

    Map<String, dynamic> payload;
    if (file.existsSync()) {
      final existing = jsonDecode(await file.readAsString());
      if (existing is Map<String, dynamic>) {
        payload = Map<String, dynamic>.from(existing);
      } else {
        payload = {'runs': <dynamic>[]};
      }
    } else {
      payload = {'runs': <dynamic>[]};
    }

    final runs = payload['runs'];
    if (runs is List) {
      runs.add(summary);
      payload['runs'] = runs;
    } else {
      payload['runs'] = [summary];
    }

    await file.writeAsString(jsonEncode(payload));
    debugPrint('Performance benchmark written to ${file.path}');
    return file.path;
  }
}
