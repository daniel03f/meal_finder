import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:meal_finder/src/services/embedding_service.dart';

img.Image solidImage(int r, int g, int b) {
  final image = img.Image(width: 224, height: 224);
  img.fill(image, color: img.ColorRgba8(r, g, b, 255));
  return image;
}

void main() {
  group('EmbeddingService', () {
    late EmbeddingService service;

    setUp(() {
      service = EmbeddingService();
    });

    group('initial state', () {
      test('isInitialized is false before initialize()', () {
        expect(service.isInitialized, isFalse);
      });

      test('two instances have independent state', () {
        final other = EmbeddingService();
        expect(service.isInitialized, isFalse);
        expect(other.isInitialized, isFalse);
        expect(identical(service, other), isFalse);
      });
    });

    group('embedImage() guard clause', () {
      test('throws StateError when called before initialize()', () async {
        final image = solidImage(0, 0, 0);
        await expectLater(
          service.embedImage(image),
          throwsA(isA<StateError>()),
        );
      });
    });
  });
  group('EmbeddingService.preprocessImage', () {
    const inputSize = EmbeddingService.inputSize; // 224

    test('output tensor has correct length (1 × H × W × 3)', () {
      final tensor = EmbeddingService.preprocessImage(solidImage(128, 128, 128));
      expect(tensor.length, equals(inputSize * inputSize * 3));
    });

    test('output is a Float32List', () {
      final tensor = EmbeddingService.preprocessImage(solidImage(0, 0, 0));
      expect(tensor, isA<Float32List>());
    });

    test('portrait image (width < height) is processed without error', () {
      final portrait = img.Image(width: 200, height: 400);
      img.fill(portrait, color: img.ColorRgba8(60, 120, 180, 255));
      final tensor = EmbeddingService.preprocessImage(portrait);
      expect(tensor.length, equals(inputSize * inputSize * 3));
    });

    test('landscape image (width > height) is processed without error', () {
      final landscape = img.Image(width: 640, height: 480);
      img.fill(landscape, color: img.ColorRgba8(200, 100, 50, 255));
      final tensor = EmbeddingService.preprocessImage(landscape);
      expect(tensor.length, equals(inputSize * inputSize * 3));
    });

    test('square image (width == height) is processed without error', () {
      final square = img.Image(width: 300, height: 300);
      img.fill(square, color: img.ColorRgba8(100, 150, 200, 255));
      final tensor = EmbeddingService.preprocessImage(square);
      expect(tensor.length, equals(inputSize * inputSize * 3));
    });

    test('pure-black image (0,0,0) maps to CLIP-normalised values', () {
      // pixel=0 → (0/255 - mean[c]) / std[c]
      final expected = [
        (0.0 - EmbeddingService.mean[0]) / EmbeddingService.std[0],
        (0.0 - EmbeddingService.mean[1]) / EmbeddingService.std[1],
        (0.0 - EmbeddingService.mean[2]) / EmbeddingService.std[2],
      ];
      final tensor = EmbeddingService.preprocessImage(solidImage(0, 0, 0));
      expect(tensor[0], closeTo(expected[0], 1e-5));
      expect(tensor[1], closeTo(expected[1], 1e-5));
      expect(tensor[2], closeTo(expected[2], 1e-5));
    });

    test('pure-white image (255,255,255) maps to CLIP-normalised values', () {
      final expected = [
        (1.0 - EmbeddingService.mean[0]) / EmbeddingService.std[0],
        (1.0 - EmbeddingService.mean[1]) / EmbeddingService.std[1],
        (1.0 - EmbeddingService.mean[2]) / EmbeddingService.std[2],
      ];
      final tensor = EmbeddingService.preprocessImage(solidImage(255, 255, 255));
      expect(tensor[0], closeTo(expected[0], 1e-5));
      expect(tensor[1], closeTo(expected[1], 1e-5));
      expect(tensor[2], closeTo(expected[2], 1e-5));
    });

    test('all pixels of a solid-colour image have identical channel values', () {
      final tensor = EmbeddingService.preprocessImage(solidImage(100, 150, 200));
      // Every stride of 3 should be identical – check a few spots
      for (int i = 0; i < tensor.length - 3; i += 3) {
        expect(tensor[i],     closeTo(tensor[0], 1e-5));
        expect(tensor[i + 1], closeTo(tensor[1], 1e-5));
        expect(tensor[i + 2], closeTo(tensor[2], 1e-5));
      }
    });

    test('different source images produce different tensors', () {
      final t1 = EmbeddingService.preprocessImage(solidImage(50,  50,  50));
      final t2 = EmbeddingService.preprocessImage(solidImage(200, 100, 30));
      expect(t1[0], isNot(closeTo(t2[0], 1e-5)));
    });
  });

  group('EmbeddingService.normalizeEmbedding', () {
    const dim = EmbeddingService.embeddingDim; // 512

    test('output has same length as input', () {
      final raw = List.filled(dim, 0.5);
      expect(EmbeddingService.normalizeEmbedding(raw), hasLength(dim));
    });

    test('output vector has L2 norm ≈ 1.0', () {
      final raw = List<double>.generate(dim, (i) => sin(i * 0.1 + 1.0));
      final norm = EmbeddingService.normalizeEmbedding(raw);
      final l2 = sqrt(norm.fold(0.0, (s, v) => s + v * v));
      expect(l2, closeTo(1.0, 1e-6));
    });

    test('already-normalised vector is unchanged (norm stays ≈ 1.0)', () {
      final raw = List<double>.generate(dim, (i) => sin(i * 0.2 + 0.5));
      final preNorm = sqrt(raw.fold(0.0, (s, v) => s + v * v));
      final unit = raw.map((v) => v / preNorm).toList();
      final result = EmbeddingService.normalizeEmbedding(unit);
      final l2 = sqrt(result.fold(0.0, (s, v) => s + v * v));
      expect(l2, closeTo(1.0, 1e-6));
    });

    test('zero vector is returned as-is (no division-by-zero)', () {
      final zero = List.filled(dim, 0.0);
      final result = EmbeddingService.normalizeEmbedding(zero);
      expect(result, equals(zero));
    });

    test('single non-zero component normalises to ±1.0', () {
      final vec = List.filled(dim, 0.0)..[0] = 5.0;
      final result = EmbeddingService.normalizeEmbedding(vec);
      expect(result[0], closeTo(1.0, 1e-6));
      for (int i = 1; i < dim; i++) {
        expect(result[i], closeTo(0.0, 1e-6));
      }
    });

    test('output values are in [-1, 1]', () {
      final raw = List<double>.generate(dim, (i) => sin(i * 0.3));
      final result = EmbeddingService.normalizeEmbedding(raw);
      for (final v in result) {
        expect(v, greaterThanOrEqualTo(-1.0 - 1e-9));
        expect(v, lessThanOrEqualTo(1.0 + 1e-9));
      }
    });

    test('negative values are preserved after normalisation', () {
      final raw = List<double>.generate(dim, (i) => i.isEven ? 1.0 : -1.0);
      final result = EmbeddingService.normalizeEmbedding(raw);
      expect(result.any((v) => v < 0), isTrue);
    });

    test('normalisation is scale-invariant: 2×v and v produce same unit vector',
        () {
      final raw = List<double>.generate(dim, (i) => sin(i * 0.05 + 0.7));
      final scaled = raw.map((v) => v * 2.0).toList();
      final n1 = EmbeddingService.normalizeEmbedding(raw);
      final n2 = EmbeddingService.normalizeEmbedding(scaled);
      for (int i = 0; i < dim; i++) {
        expect(n1[i], closeTo(n2[i], 1e-6));
      }
    });
  });
}

