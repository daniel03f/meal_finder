import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:meal_finder/src/models/classification_result.dart';
import 'package:meal_finder/src/models/crop_data.dart';
import 'package:meal_finder/src/presentation/controllers/camera_inference_controller.dart';
import 'package:meal_finder/src/presentation/widgets/camera_inference_content.dart';
import 'package:meal_finder/src/presentation/widgets/model_loading_overlay.dart';
import 'package:meal_finder/src/services/class_manager.dart';
import 'package:meal_finder/src/services/database_service.dart';
import 'package:meal_finder/src/utils/image_utils.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';
import 'package:ultralytics_yolo/widgets/yolo_overlay.dart';

class _FakeDatabaseService extends DatabaseService {
  @override
  Future<List<CropData>> getClassCrops(List<String> classNames) async => [];

  @override
  Future<List<String>> getAllClasses() async => [];
}

class _FakeClassManager extends ClassManager {
  _FakeClassManager() : super(_FakeDatabaseService());

  @override
  bool get isInitialized => true;

  @override
  Future<ClassificationResult> classifyCrop({
    required img.Image cropImage,
    required List<String> classNames,
  }) async =>
      ClassificationResult(predictedClass: '', confidence: 0.0);
}

/// A [CameraInferenceController] whose observable state can be configured
/// directly, so widget tests do not depend on model loading or platform
/// channels.
class _FakeController extends CameraInferenceController {
  final String? _fakeModelPath;
  final bool _fakeIsModelLoading;

  /// Optional override for [onDetectionResults]. Receives the already-
  /// converted [YOLOResult] list and returns the best result (or null).
  final YOLOResult? Function(List<YOLOResult> results)? detectionHandler;

  /// The last [results] argument received by [onDetectionResults].
  List<YOLOResult>? lastReceivedDetections;

  _FakeController({
    String? modelPath,
    bool isModelLoading = false,
    this.detectionHandler,
  })  : _fakeModelPath = modelPath,
        _fakeIsModelLoading = isModelLoading,
        super(classManager: _FakeClassManager());

  @override
  String? get modelPath => _fakeModelPath;

  @override
  bool get isModelLoading => _fakeIsModelLoading;

  @override
  Future<YOLOResult?> onDetectionResults(
    List<YOLOResult> results,
    Uint8List imageList,
  ) async {
    lastReceivedDetections = results;
    return detectionHandler?.call(results);
  }

  // Suppress FPS notifications that would otherwise trigger unnecessary rebuilds.
  @override
  void onPerformanceMetrics(double fps) {}
}

/// Builds a [CameraInferenceContent] widget inside a [MaterialApp] and returns
/// the [GlobalKey] giving access to its public state.
Future<GlobalKey<CameraInferenceContentState>> _pumpContent(
  WidgetTester tester, {
  required _FakeController controller,
  Widget yoloViewOverride = const SizedBox.expand(),
}) async {
  final key = GlobalKey<CameraInferenceContentState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CameraInferenceContent(
          key: key,
          controller: controller,
          yoloView: yoloViewOverride,
        ),
      ),
    ),
  );
  return key;
}

/// Creates a minimal [YOLOResult] with the supplied bounding boxes.
YOLOResult _makeResult({
  Rect boundingBox = const Rect.fromLTRB(50, 50, 150, 150),
  Rect normalizedBox = const Rect.fromLTRB(0.1, 0.1, 0.3, 0.3),
  double confidence = 0.9,
  String className = 'apple',
  int classIndex = 0,
}) =>
    YOLOResult(
      boundingBox: boundingBox,
      normalizedBox: normalizedBox,
      confidence: confidence,
      className: className,
      classIndex: classIndex,
    );

/// Raw detection map in the format that [YOLOView.onStreamingData] delivers
/// (and that [MapConverter.convertToYOLOResults] consumes).
Map<String, dynamic> _rawDetectionMap({
  required Rect boundingBox,
  required Rect normalizedBox,
  double confidence = 0.9,
  String className = 'apple',
  int classIndex = 0,
}) =>
    {
      'boundingBox': {
        'left': boundingBox.left,
        'top': boundingBox.top,
        'right': boundingBox.right,
        'bottom': boundingBox.bottom,
      },
      'normalizedBox': {
        'left': normalizedBox.left,
        'top': normalizedBox.top,
        'right': normalizedBox.right,
        'bottom': normalizedBox.bottom,
      },
      'confidence': confidence,
      'className': className,
      'classIndex': classIndex,
    };

/// Minimal valid [Uint8List] that is accepted as the originalImage field but
/// intentionally does NOT carry valid JPEG data (only used in fake controllers
/// that ignore the image bytes).
final _dummyImage = Uint8List(4);

/// A named stand-in for the real [YOLOView]. Using a distinct type lets tests
/// unambiguously check for the camera view in the tree without confusing it
/// with other [SizedBox] or [Container] widgets.
class _FakeCameraView extends StatelessWidget {
  const _FakeCameraView();
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

void main() {
  group('CameraInferenceContent – branching logic', () {
    testWidgets(
        'shows "No model loaded" when modelPath is null and not loading',
        (tester) async {
      final controller = _FakeController();
      await _pumpContent(tester, controller: controller);

      expect(find.text('No model loaded'), findsOneWidget);
      expect(find.byType(ModelLoadingOverlay), findsNothing);
    });

    testWidgets('shows ModelLoadingOverlay while isModelLoading is true',
        (tester) async {
      final controller = _FakeController(isModelLoading: true);
      await _pumpContent(tester, controller: controller);

      expect(find.byType(ModelLoadingOverlay), findsOneWidget);
      expect(find.text('No model loaded'), findsNothing);
    });

    testWidgets('shows camera stack when model is ready (modelPath not null)',
        (tester) async {
      final controller = _FakeController(modelPath: 'fake/model.tflite');
      await _pumpContent(tester, controller: controller);

      // The yoloViewOverride (SizedBox.expand) should be in the tree instead
      // of the real YOLOView.
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('No model loaded'), findsNothing);
      expect(find.byType(ModelLoadingOverlay), findsNothing);
    });

    testWidgets('no YOLOOverlay present before any streaming data arrives',
        (tester) async {
      final controller = _FakeController(modelPath: 'fake/model.tflite');
      await _pumpContent(tester, controller: controller);

      expect(find.byType(YOLOOverlay), findsNothing);
    });
  });

  group('CameraInferenceContent – bestObject overlay', () {
    testWidgets(
        'YOLOOverlay appears after handleStreamingData returns a bestObject',
        (tester) async {
      final detection = _makeResult();
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => detection,
      );
      final key = await _pumpContent(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(
              boundingBox: detection.boundingBox,
              normalizedBox: detection.normalizedBox)
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      expect(find.byType(YOLOOverlay), findsOneWidget);
    });

    testWidgets(
        'YOLOOverlay receives exactly the one result returned by the controller',
        (tester) async {
      final detection = _makeResult(
        boundingBox: const Rect.fromLTRB(10, 20, 110, 220),
        normalizedBox: const Rect.fromLTRB(0.05, 0.1, 0.55, 0.6),
        className: 'banana',
        confidence: 0.92,
      );
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => detection,
      );
      final key = await _pumpContent(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(
              boundingBox: detection.boundingBox,
              normalizedBox: detection.normalizedBox)
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      final overlay = tester.widget<YOLOOverlay>(find.byType(YOLOOverlay));
      expect(overlay.detections.length, 1);
    });

    testWidgets(
        'bestObject bounding box in YOLOOverlay is scaled from normalizedBox '
        'to the widget dimensions (bestObject sits over the detected region)',
        (tester) async {
      const bbox = Rect.fromLTRB(30.0, 40.0, 200.0, 180.0);
      const normBox = Rect.fromLTRB(0.06, 0.08, 0.4, 0.36);

      // Controller echoes the first detection back as the bestObject so the
      // bounding box is guaranteed to be the one from onStreamingData.
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (results) =>
            results.isNotEmpty ? results.first : null,
      );
      final key = await _pumpContent(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(
              boundingBox: bbox, normalizedBox: normBox, className: 'orange'),
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      // The Flutter test viewport is 800×600 logical pixels.
      // The LayoutBuilder wrapping the Stack receives these full dimensions,
      // so boundingBox must match the FILL_CENTER coordinate transformation.
      const testWidth = 800.0;
      const testHeight = 600.0;
      final expectedBox = normalizedToScreenRect(normBox, testWidth, testHeight);
      final overlay = tester.widget<YOLOOverlay>(find.byType(YOLOOverlay));
      final drawn = overlay.detections.first;
      expect(drawn.normalizedBox, equals(normBox));
      expect(
        drawn.boundingBox,
        equals(expectedBox),
      );
    });

    testWidgets(
        'detections passed via onStreamingData are congruent with the drawn '
        'bounding boxes – multiple detections, controller picks one by index',
        (tester) async {
      const bbox0 = Rect.fromLTRB(0, 0, 50, 50);
      const bbox1 = Rect.fromLTRB(100, 100, 200, 200);
      const normBox0 = Rect.fromLTRB(0.0, 0.0, 0.1, 0.1);
      const normBox1 = Rect.fromLTRB(0.2, 0.2, 0.4, 0.4);

      // Controller picks the second detection.
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (results) => results.length >= 2 ? results[1] : null,
      );
      final key = await _pumpContent(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(boundingBox: bbox0, normalizedBox: normBox0),
          _rawDetectionMap(
              boundingBox: bbox1, normalizedBox: normBox1, className: 'mango'),
        ],
        'fps': 25.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      final overlay = tester.widget<YOLOOverlay>(find.byType(YOLOOverlay));
      // normalizedBox identifies which detection was picked; boundingBox is
      // scaled to the 800×600 test viewport via FILL_CENTER transformation.
      final expectedBox = normalizedToScreenRect(normBox1, 800.0, 600.0);
      expect(overlay.detections.first.normalizedBox, equals(normBox1));
      expect(
        overlay.detections.first.boundingBox,
        equals(expectedBox),
      );
    });

    testWidgets('YOLOOverlay is not shown when controller returns null',
        (tester) async {
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => null,
      );
      final key = await _pumpContent(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(
              boundingBox: const Rect.fromLTRB(0, 0, 100, 100),
              normalizedBox: const Rect.fromLTRB(0, 0, 0.2, 0.2)),
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      expect(find.byType(YOLOOverlay), findsNothing);
    });

    testWidgets(
        'no overlay when originalImage is missing (null) – exception is swallowed',
        (tester) async {
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => _makeResult(),
      );
      final key = await _pumpContent(tester, controller: controller);

      // Pass null for originalImage – the null-bang inside handleStreamingData
      // will throw, which should be caught and logged without crashing.
      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(
              boundingBox: const Rect.fromLTRB(0, 0, 100, 100),
              normalizedBox: const Rect.fromLTRB(0, 0, 0.2, 0.2)),
        ],
        'fps': 30.0,
        // no 'originalImage' key → defaults to null
      });
      await tester.pump();

      expect(find.byType(YOLOOverlay), findsNothing);
    });

    testWidgets(
        'YOLOOverlay is inside a Positioned.fill overlaid on the camera view',
        (tester) async {
      final detection = _makeResult();
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => detection,
      );
      final key = await _pumpContent(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(
              boundingBox: detection.boundingBox,
              normalizedBox: detection.normalizedBox)
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      // The YOLOOverlay must be the child of a Positioned.fill widget which
      // itself lives inside the Stack that contains the camera view.
      final positioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byType(YOLOOverlay),
          matching: find.byType(Positioned),
        ),
      );
      // Positioned.fill sets all four edges to 0.
      expect(positioned.left, 0.0);
      expect(positioned.top, 0.0);
      expect(positioned.right, 0.0);
      expect(positioned.bottom, 0.0);
    });

    testWidgets(
        'previous bestObject is replaced when a new streaming result arrives',
        (tester) async {
      const bbox1 = Rect.fromLTRB(0, 0, 50, 50);
      const bbox2 = Rect.fromLTRB(200, 200, 300, 300);
      const norm1 = Rect.fromLTRB(0.0, 0.0, 0.1, 0.1);
      const norm2 = Rect.fromLTRB(0.4, 0.4, 0.6, 0.6);

      int call = 0;
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) {
          call++;
          return call == 1
              ? _makeResult(boundingBox: bbox1, normalizedBox: norm1)
              : _makeResult(boundingBox: bbox2, normalizedBox: norm2);
        },
      );
      final key = await _pumpContent(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(boundingBox: bbox1, normalizedBox: norm1)
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      // First result shown.
      expect(
        tester
            .widget<YOLOOverlay>(find.byType(YOLOOverlay))
            .detections
            .first
            .normalizedBox,
        equals(norm1),
      );

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(boundingBox: bbox2, normalizedBox: norm2)
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      // Second result replaces the first.
      expect(
        tester
            .widget<YOLOOverlay>(find.byType(YOLOOverlay))
            .detections
            .first
            .normalizedBox,
        equals(norm2),
      );
    });
  });

  group('CameraInferenceContent – streaming data conversion', () {
    testWidgets(
        'handleStreamingData forwards all raw detections to onDetectionResults',
        (tester) async {
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => null,
      );
      final key = await _pumpContent(tester, controller: controller);

      const bbox0 = Rect.fromLTRB(10, 10, 60, 60);
      const norm0 = Rect.fromLTRB(0.02, 0.02, 0.12, 0.12);
      const bbox1 = Rect.fromLTRB(70, 70, 130, 130);
      const norm1 = Rect.fromLTRB(0.14, 0.14, 0.26, 0.26);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(boundingBox: bbox0, normalizedBox: norm0),
          _rawDetectionMap(
              boundingBox: bbox1, normalizedBox: norm1, className: 'peach'),
        ],
        'fps': 20.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      expect(controller.lastReceivedDetections?.length, 2);
    });

    testWidgets(
        'bounding boxes received by onDetectionResults match the raw maps '
        'from onStreamingData (full-pipeline congruence check)',
        (tester) async {
      const bbox = Rect.fromLTRB(15.0, 25.0, 115.0, 225.0);
      const normBox = Rect.fromLTRB(0.03, 0.05, 0.23, 0.45);

      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => null, // we only care about what was received
      );
      final key = await _pumpContent(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(boundingBox: bbox, normalizedBox: normBox),
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      final received = controller.lastReceivedDetections!;
      expect(received.length, 1);
      expect(received.first.boundingBox, equals(bbox));
      expect(received.first.normalizedBox, equals(normBox));
    });

    testWidgets(
        'handles empty detections list gracefully and forwards zero results',
        (tester) async {
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => null,
      );
      final key = await _pumpContent(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': <dynamic>[],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      expect(controller.lastReceivedDetections, isEmpty);
      expect(find.byType(YOLOOverlay), findsNothing);
    });

    testWidgets(
        'handles missing detections key gracefully – forwards empty list',
        (tester) async {
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => null,
      );
      final key = await _pumpContent(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        // no 'detections' key
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      // lastReceivedDetections is [] (not null) because MapConverter gets [].
      expect(controller.lastReceivedDetections, isEmpty);
    });
  });

  group(
      'CameraInferenceContent – stack composition (camera + overlay co-presence)',
      () {
    // Use the named stub so tests can unambiguously find the camera view.
    Future<GlobalKey<CameraInferenceContentState>> pumpWithStub(
      WidgetTester tester, {
      required _FakeController controller,
    }) =>
        _pumpContent(
          tester,
          controller: controller,
          yoloViewOverride: const _FakeCameraView(),
        );

    testWidgets(
        'when model is ready and no bestObject: camera view is shown, '
        'but no YOLOOverlay', (tester) async {
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => null,
      );
      await pumpWithStub(tester, controller: controller);

      expect(find.byType(_FakeCameraView), findsOneWidget);
      expect(find.byType(YOLOOverlay), findsNothing);
    });

    testWidgets(
        'when bestObject arrives: camera view AND YOLOOverlay are both in the '
        'tree at the same time (overlay does not replace the camera view)',
        (tester) async {
      final detection = _makeResult();
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => detection,
      );
      final key = await pumpWithStub(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(
              boundingBox: detection.boundingBox,
              normalizedBox: detection.normalizedBox)
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      expect(find.byType(_FakeCameraView), findsOneWidget,
          reason: 'Camera view must still be present after overlay appears');
      expect(find.byType(YOLOOverlay), findsOneWidget,
          reason: 'YOLOOverlay must appear on top of the camera view');
    });

    testWidgets(
        'camera view is a direct Stack child behind the overlay – '
        'YOLOOverlay is in a Positioned sibling, not replacing the camera view',
        (tester) async {
      final detection = _makeResult();
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => detection,
      );
      final key = await pumpWithStub(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(
              boundingBox: detection.boundingBox,
              normalizedBox: detection.normalizedBox)
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      // Both the camera stub and the YOLOOverlay must share the same Stack.
      final stack = tester.widget<Stack>(
        find.ancestor(
          of: find.byType(_FakeCameraView),
          matching: find.byType(Stack),
        ),
      );
      // The same Stack must also be an ancestor of YOLOOverlay.
      final stackOfOverlay = tester.widget<Stack>(
        find.ancestor(
          of: find.byType(YOLOOverlay),
          matching: find.byType(Stack),
        ),
      );
      expect(identical(stack, stackOfOverlay), isTrue,
          reason: 'Camera view and overlay must share the same Stack');
    });

    testWidgets(
        'YOLOOverlay renders with showConfidence and showClassName enabled',
        (tester) async {
      final detection = _makeResult();
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => detection,
      );
      final key = await pumpWithStub(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(
              boundingBox: detection.boundingBox,
              normalizedBox: detection.normalizedBox)
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      final overlay = tester.widget<YOLOOverlay>(find.byType(YOLOOverlay));
      expect(overlay.showConfidence, isTrue);
      expect(overlay.showClassName, isTrue);
    });

    testWidgets(
        'YOLOOverlay uses green bounding box color from theme',
        (tester) async {
      final detection = _makeResult();
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) => detection,
      );
      final key = await pumpWithStub(tester, controller: controller);

      await key.currentState!.handleStreamingData({
        'detections': [
          _rawDetectionMap(
              boundingBox: detection.boundingBox,
              normalizedBox: detection.normalizedBox)
        ],
        'fps': 30.0,
        'originalImage': _dummyImage,
      });
      await tester.pump();

      final overlay = tester.widget<YOLOOverlay>(find.byType(YOLOOverlay));
      expect(overlay.theme.boundingBoxColor, equals(Colors.green));
    });

    testWidgets(
        'camera view remains visible across multiple streaming frames '
        '(not removed after first bestObject update)', (tester) async {
      int call = 0;
      final controller = _FakeController(
        modelPath: 'fake/model.tflite',
        detectionHandler: (_) {
          call++;
          return call.isOdd ? _makeResult() : null;
        },
      );
      final key = await pumpWithStub(tester, controller: controller);

      for (int i = 0; i < 4; i++) {
        await key.currentState!.handleStreamingData({
          'detections': [
            _rawDetectionMap(
                boundingBox: _makeResult().boundingBox,
                normalizedBox: _makeResult().normalizedBox)
          ],
          'fps': 30.0,
          'originalImage': _dummyImage,
        });
        await tester.pump();
        expect(find.byType(_FakeCameraView), findsOneWidget,
            reason: 'Frame $i: camera view must always be visible');
      }
    });
  });
}
