import 'dart:math' show sqrt;
import 'package:image/image.dart' as img;
import 'package:meal_finder/src/utils/image_utils.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';

/// Service for creating image embeddings using TFLite model
class EmbeddingService {
  late final Interpreter _interpreter;

  // Model configuration for DINOv3
  static const int inputSize = 98; // Custom image size for DINOv3 models
  static const int embeddingDim = 384; // Output embedding dimension

  // DINOv3 normalization values
  static const List<double> mean = [0.485, 0.456, 0.406];
  static const List<double> std = [0.229, 0.224, 0.225];

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initialize the TFLite interpreter with the embedding model
  Future<void> initialize(
      {String modelPath =
          'assets/ml/models/dinov3_vits16_pretrain_lvd1689m-08c60483_float32.tflite'}) async {
    try {
      _interpreter = await Interpreter.fromAsset(
        modelPath,
        options: InterpreterOptions() ..threads = 4
      );
      _interpreter.allocateTensors();

      _isInitialized = true;
      debugPrint('Embedding model loaded successfully');
    } catch (e) {
      debugPrint('Failed to load embedding model: $e');
      throw Exception('Failed to load embedding model: $e');
    }
  }

  /// Create embedding from a decoded image
  Future<List<double>> embedImage(img.Image image) async {
    if (!_isInitialized) {
      throw StateError(
          'EmbeddingService not initialized. Call initialize() first.');
    }

    try {
      final input = await compute(EmbeddingService.preprocessImage, image);

      // Write input tensor into the buffer and run inference
      _interpreter.getInputTensor(0).data = input.buffer.asUint8List();
      _interpreter.invoke();

      // Read output tensor and convert to List<double>
      final rawOutput = _interpreter.getOutputTensor(0).data.buffer.asFloat32List();

      final embedding = rawOutput.toList();
      return EmbeddingService.normalizeEmbedding(embedding);
    } catch (e) {
      debugPrint('Error embedding image: $e');
      return [];
    }
  }

  /// Preprocess image for the model
  @visibleForTesting
  static Float32List preprocessImage(img.Image image, {int targetSize = inputSize}) {
    final resized = scaleCropImage(image, targetSize);

    return toTensor(resized);
  }

  // Convert the resized image to a normalized tensor format expected by the model
  @visibleForTesting
  static Float32List toTensor(img.Image image) {
    // Create a shaped 4D tensor [1, height, width, channels]
    final tensorSize = 1 * inputSize * inputSize * 3;
    final tensorBytes = Float32List(tensorSize);
    int index = 0;

    // Normalize with mean and std for each channel [R, G, B]
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);
        tensorBytes[index++] = (pixel.r / 255.0 - mean[0]) / std[0];
        tensorBytes[index++] = (pixel.g / 255.0 - mean[1]) / std[1];
        tensorBytes[index++] = (pixel.b / 255.0 - mean[2]) / std[2];
      }
    }

    return tensorBytes;
  }

  /// Normalize the embedding vector using L2 normalization
  @visibleForTesting
  static List<double> normalizeEmbedding(List<double> embedding) {
    // Calculate L2 norm
    double norm = 0.0;
    for (final value in embedding) {
      norm += value * value;
    }
    norm = sqrt(norm);

    // Avoid division by zero
    if (norm == 0.0) return embedding;

    // Normalize
    return embedding.map((value) => value / norm).toList();
  }

  /// Dispose of the interpreter and free resources
  void dispose() {
    _interpreter.close();
    _isInitialized = false;
  }
}
