import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:meal_finder/src/models/classification_result.dart';
import 'package:meal_finder/src/services/class_manager.dart';
import 'package:meal_finder/src/services/database_service.dart';
import 'package:meal_finder/src/services/embedding_service.dart';

class _FakeDatabaseService extends DatabaseService {
  ClassificationResult? findBestClassResult;

  _FakeDatabaseService({this.findBestClassResult});

  @override
  Future<ClassificationResult> findBestClass({
    required List<double> queryEmbedding,
    required List<String> classNames,
    int limitPerClass = 10,
  }) async {
    if (findBestClassResult != null) return findBestClassResult!;
    return ClassificationResult(predictedClass: '', confidence: 0.0);
  }
}

class _FakeEmbeddingService extends EmbeddingService {
  final bool _fakeInitialized;
  final List<double> _embedding;

  _FakeEmbeddingService({
    bool initialized = true,
    List<double>? embedding,
  })  : _fakeInitialized = initialized,
        _embedding = embedding ?? List.filled(512, 0.0);

  @override
  bool get isInitialized => _fakeInitialized;

  @override
  Future<List<double>> embedImage(img.Image image) async => _embedding;

  @override
  void dispose() {} // no interpreter to close
}

img.Image _solidImage() {
  final image = img.Image(width: 32, height: 32);
  img.fill(image, color: img.ColorRgba8(128, 128, 128, 255));
  return image;
}

void main() {
  group('ClassManager.isInitialized', () {
    test('delegates to EmbeddingService.isInitialized (false by default)', () {
      final cm = ClassManager(
        _FakeDatabaseService(),
        embeddingService: _FakeEmbeddingService(initialized: false),
      );
      expect(cm.isInitialized, isFalse);
    });

    test('reports true when fake embedder is initialized', () {
      final cm = ClassManager(
        _FakeDatabaseService(),
        embeddingService: _FakeEmbeddingService(initialized: true),
      );
      expect(cm.isInitialized, isTrue);
    });
  });

  group('ClassManager.classifyCrop guard', () {
    test('throws StateError when not initialized', () async {
      final cm = ClassManager(
        _FakeDatabaseService(),
        embeddingService: _FakeEmbeddingService(initialized: false),
      );
      await expectLater(
        cm.classifyCrop(cropImage: _solidImage(), classNames: ['pizza']),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ClassManager.classifyCrop (with fakes)', () {
    test('delegates to findBestClass with embedding from EmbeddingService',
        () async {
      final db = _FakeDatabaseService(
        findBestClassResult: ClassificationResult(
          predictedClass: 'pizza',
          confidence: 1.0,
        ),
      );
      final cm = ClassManager(
        db,
        embeddingService: _FakeEmbeddingService(),
      );

      final result = await cm.classifyCrop(
        cropImage: _solidImage(),
        classNames: ['pizza'],
      );

      expect(result.predictedClass, 'pizza');
      expect(result.confidence, closeTo(1.0, 1e-5));
    });

    test('returns empty result when findBestClass returns empty', () async {
      final db = _FakeDatabaseService(
        findBestClassResult: ClassificationResult(
          predictedClass: '',
          confidence: 0.0,
        ),
      );
      final cm = ClassManager(
        db,
        embeddingService: _FakeEmbeddingService(),
      );

      final result = await cm.classifyCrop(
        cropImage: _solidImage(),
        classNames: ['pizza'],
      );

      expect(result.predictedClass, '');
      expect(result.confidence, 0.0);
    });

    test('returns the classification result from findBestClass',
        () async {
      final db = _FakeDatabaseService(
        findBestClassResult: ClassificationResult(
          predictedClass: 'pizza',
          confidence: 0.95,
        ),
      );
      final cm = ClassManager(
        db,
        embeddingService: _FakeEmbeddingService(),
      );

      final result = await cm.classifyCrop(
        cropImage: _solidImage(),
        classNames: ['pizza', 'burger'],
      );

      expect(result.predictedClass, 'pizza');
      expect(result.confidence, 0.95);
    });
  });
}
