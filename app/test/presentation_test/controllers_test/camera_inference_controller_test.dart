import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:meal_finder/src/models/classification_result.dart';
import 'package:meal_finder/src/models/crop_data.dart';
import 'package:meal_finder/src/presentation/controllers/camera_inference_controller.dart';
import 'package:meal_finder/src/services/class_manager.dart';
import 'package:meal_finder/src/services/database_service.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';

class _FakeDatabaseService extends DatabaseService {
  @override
  Future<List<CropData>> getClassCrops(List<String> classNames) async => [];

  @override
  Future<List<String>> getAllClasses() async => [];
}

class _FakeClassManager extends ClassManager {
  final bool _fakeInitialized;
  final List<ClassificationResult> _results;
  int _callIndex = 0;
  int classifyCropCallCount = 0;

  _FakeClassManager({
    bool initialized = true,
    List<ClassificationResult>? results,
  })  : _fakeInitialized = initialized,
        _results = results ??
            [ClassificationResult(predictedClass: '', confidence: 0.0)],
        super(_FakeDatabaseService());

  @override
  bool get isInitialized => _fakeInitialized;

  @override
  Future<ClassificationResult> classifyCrop({
    required img.Image cropImage,
    required List<String> classNames,
  }) async {
    classifyCropCallCount++;
    if (_callIndex < _results.length) return _results[_callIndex++];
    return _results.last;
  }

  void setResult(ClassificationResult r) {
    _results
      ..clear()
      ..add(r);
    _callIndex = 0;
  }
}


/// Solid-colour image of the requested size.
img.Image makeImage(int w, int h, {int r = 128, int g = 128, int b = 128}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgba8(r, g, b, 255));
  return image;
}

/// Encodes an img.Image to a JPEG byte array (valid input for onDetectionResults).
Uint8List encodeJpeg(img.Image image) =>
    Uint8List.fromList(img.encodeJpg(image));

/// Minimal YOLOResult factory.
YOLOResult makeResult({
  Rect? normalizedBox,
  double confidence = 0.9,
  String className = 'item',
  int classIndex = 0,
}) =>
    YOLOResult(
      boundingBox: Rect.zero,
      normalizedBox: normalizedBox ?? const Rect.fromLTWH(0.1, 0.1, 0.5, 0.5),
      confidence: confidence,
      className: className,
      classIndex: classIndex,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CameraInferenceController.onDetectionResults guard clauses', () {
    final jpegBytes = encodeJpeg(makeImage(224, 224));

    test('returns null when controller is disposed', () async {
      final controller = CameraInferenceController(
        selectedLabels: ['pizza'],
        classManager: _FakeClassManager(),
      );
      controller.dispose();
      final result = await controller.onDetectionResults([makeResult()], jpegBytes);
      expect(result, isNull);
    });

    test('returns null when ClassManager is not initialized', () async {
      final controller = CameraInferenceController(
        selectedLabels: ['pizza'],
        classManager: _FakeClassManager(initialized: false),
      );
      final result = await controller.onDetectionResults([makeResult()], jpegBytes);
      expect(result, isNull);
      controller.dispose();
    });

    test('returns null when selectedLabels is null', () async {
      // No selectedLabels → _selectedLabels == null
      final controller = CameraInferenceController(
        classManager: _FakeClassManager(),
      );
      final result = await controller.onDetectionResults([makeResult()], jpegBytes);
      expect(result, isNull);
      controller.dispose();
    });

    test('returns null when selectedLabels is empty', () async {
      final controller = CameraInferenceController(
        selectedLabels: [],
        classManager: _FakeClassManager(),
      );
      final result = await controller.onDetectionResults([makeResult()], jpegBytes);
      expect(result, isNull);
      controller.dispose();
    });

    test('returns null when results list is empty', () async {
      final controller = CameraInferenceController(
        selectedLabels: ['pizza'],
        classManager: _FakeClassManager(),
      );
      final result = await controller.onDetectionResults([], jpegBytes);
      expect(result, isNull);
      controller.dispose();
    });

    test('detectionCount is updated when result count changes', () async {
      final controller = CameraInferenceController(
        classManager: _FakeClassManager(initialized: false),
      );
      expect(controller.detectionCount, 0);
      await controller.onDetectionResults(
          [makeResult(), makeResult()], jpegBytes);
      expect(controller.detectionCount, 2);
      controller.dispose();
    });

    test('detectionCount is not updated when count is unchanged', () async {
      final controller = CameraInferenceController(
        classManager: _FakeClassManager(initialized: false),
      );
      // First call → sets count to 1
      await controller.onDetectionResults([makeResult()], jpegBytes);
      final notifyCount = <int>[];
      controller.addListener(() => notifyCount.add(controller.detectionCount));
      // Second call with same number of results → no extra notification
      await controller.onDetectionResults([makeResult()], jpegBytes);
      expect(notifyCount, isEmpty);
      controller.dispose();
    });
  });

  group('CameraInferenceController.processClassifications', () {
    final testImage = makeImage(224, 224);

    test('returns null when confidence is below 0.85', () async {
      final fake = _FakeClassManager(
        results: [ClassificationResult(predictedClass: 'pizza', confidence: 0.5)],
      );
      final controller = CameraInferenceController(
        selectedLabels: ['pizza'],
        classManager: fake,
      );
      final result = await controller.processClassifications([makeResult()], testImage);
      expect(result, isNull);
      controller.dispose();
    });

    test('returns YOLOResult when classification confidence is >= 0.85', () async {
      final fake = _FakeClassManager(
        results: [ClassificationResult(predictedClass: 'pizza', confidence: 0.9)],
      );
      final controller = CameraInferenceController(
        selectedLabels: ['pizza'],
        classManager: fake,
      );
      final result = await controller.processClassifications([makeResult()], testImage);
      expect(result, isNotNull);
      expect(result!.className, 'pizza');
      controller.dispose();
    });

    test('returned confidence equals classification_conf × detection_conf', () async {
      const classConf = 0.9;
      const detConf = 0.8;
      final fake = _FakeClassManager(
        results: [ClassificationResult(predictedClass: 'pizza', confidence: classConf)],
      );
      final controller = CameraInferenceController(
        selectedLabels: ['pizza'],
        classManager: fake,
      );
      final result = await controller.processClassifications(
          [makeResult(confidence: detConf)], testImage);
      expect(result, isNotNull);
      expect(result!.confidence, closeTo(classConf * detConf, 1e-6));
      controller.dispose();
    });

    test('empty results list returns null', () async {
      final fake = _FakeClassManager(
        results: [ClassificationResult(predictedClass: 'pizza', confidence: 0.95)],
      );
      final controller = CameraInferenceController(
        selectedLabels: ['pizza'],
        classManager: fake,
      );
      final result = await controller.processClassifications([], testImage);
      expect(result, isNull);
      controller.dispose();
    });

    test('returns null when predictedClass is empty string (even above 0.85)', () async {
      final fake = _FakeClassManager(
        results: [ClassificationResult(predictedClass: '', confidence: 0.95)],
      );
      final controller = CameraInferenceController(
        selectedLabels: ['pizza'],
        classManager: fake,
      );
      final result = await controller.processClassifications([makeResult()], testImage);
      expect(result, isNull);
      controller.dispose();
    });

    test('breaks early after first result >= 0.85 (only one classifyCrop call)', () async {
      final fake = _FakeClassManager(
        results: [ClassificationResult(predictedClass: 'pizza', confidence: 0.95)],
      );
      final controller = CameraInferenceController(
        selectedLabels: ['pizza'],
        classManager: fake,
      );
      await controller.processClassifications(
          [makeResult(), makeResult(), makeResult()], testImage);
      expect(fake.classifyCropCallCount, 1);
      controller.dispose();
    });

    test('processes multiple results and picks the one with highest confidence', () async {
      // Two results: first below 0.85, second above 0.85
      final fake = _FakeClassManager(
        results: [
          ClassificationResult(predictedClass: 'pizza', confidence: 0.7),
          ClassificationResult(predictedClass: 'burger', confidence: 0.9),
        ],
      );
      final controller = CameraInferenceController(
        selectedLabels: ['pizza', 'burger'],
        classManager: fake,
      );
      final result = await controller.processClassifications(
          [makeResult(className: 'a'), makeResult(className: 'b')], testImage);
      expect(result, isNotNull);
      expect(result!.className, 'burger');
      controller.dispose();
    });

    test('classIndex and normalizedBox are preserved from the original detection', () async {
      const boxRect = Rect.fromLTWH(0.1, 0.2, 0.3, 0.4);
      final fake = _FakeClassManager(
        results: [ClassificationResult(predictedClass: 'pizza', confidence: 0.9)],
      );
      final controller = CameraInferenceController(
        selectedLabels: ['pizza'],
        classManager: fake,
      );
      final detection = makeResult(
          normalizedBox: boxRect, classIndex: 42, confidence: 1.0);
      final result =
          await controller.processClassifications([detection], testImage);
      expect(result, isNotNull);
      expect(result!.classIndex, 42);
      expect(result.normalizedBox, boxRect);
      controller.dispose();
    });
  });
}
