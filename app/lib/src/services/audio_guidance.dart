import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';

class AudioGuidanceService  {
  final FlutterTts _flutterTts;

  int? _lastAnnouncedId;
  DateTime _lastAnnounceTime = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _announceCooldown = Duration(milliseconds: 1500);

  AudioGuidanceService({FlutterTts? tts}) : _flutterTts = tts ?? FlutterTts();

  Future<void> guideToObject(YOLOResult detectedObject) async {
    try {
      String direction = getDirection(detectedObject.normalizedBox);

      final now = DateTime.now();
      if (_lastAnnouncedId == detectedObject.classIndex &&
        now.difference(_lastAnnounceTime) < _announceCooldown) {
        // Skip announcement if we're in the cooldown period
        return;
      }
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.setLanguage('en-US');

      await _flutterTts.setSpeechRate(0.25);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      
      await _flutterTts.speak('${detectedObject.className} is${direction.contains('straight ahead') ? '' : ' to the'} $direction');
      _lastAnnouncedId = detectedObject.classIndex;
      _lastAnnounceTime = now;
      
    } catch (e) {
      debugPrint('Error guiding to object: $e');
    }
  }

  // Get direction based on the rect with normalized coordinates (0 to 1)
  // The image is split into a 3×3 grid of equal thirds
  @visibleForTesting
  String getDirection(Rect rect) {
    final centerX = rect.left + rect.width / 2;
    final centerY = rect.top + rect.height / 2;
    const double third = 1.0 / 3.0;
    const double twoThirds = 2.0 / 3.0;

    String horizontal;
    if (centerX < third) {
      horizontal = 'left';
    } else if (centerX > twoThirds) {
      horizontal = 'right';
    } else {
      horizontal = 'center';
    }

    String vertical;
    if (centerY < third) {
      vertical = 'up';
    } else if (centerY > twoThirds) {
      vertical = 'down';
    } else {
      vertical = 'center';
    }

    if (horizontal == 'center' && vertical == 'center') {
      return 'straight ahead';
    } else if (horizontal == 'center') {
      return vertical == 'up' ? 'up above' : 'down below';
    } else if (vertical == 'center') {
      return horizontal;
    } else {
      return '$horizontal, ${vertical == 'up' ? 'up above' : 'down below'}';
    }
  }
}