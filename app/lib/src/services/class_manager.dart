import 'package:image/image.dart' as img;

import '../models/classification_result.dart';
import 'database_service.dart';
import 'embedding_service.dart';

/// Manages classes and their assigned crops
class ClassManager {
  final DatabaseService _db;
  final EmbeddingService _embedder;

  ClassManager(this._db, {EmbeddingService? embeddingService})
      : _embedder = embeddingService ?? EmbeddingService();

  /// Initialize the ClassManager and its embedding service
  Future<void> initialize() async {
    await _embedder.initialize();
    await _db.database; // Ensure DB is initialized with vector extension
  }

  /// Check if the manager is initialized
  bool get isInitialized => _embedder.isInitialized;

  /// Classifies a crop from a decoded image
  ///
  /// [cropImage]: The crop as a decoded img.Image
  /// [className]: Class label to limit search within a class
  /// [topK]: Number of similar crops to consider for voting (default: 5)
  ///
  /// Returns: ClassificationResult with predicted_class and confidence
  Future<ClassificationResult> classifyCrop({
    required img.Image cropImage,
    required List<String> classNames,
  }) async {
    if (!isInitialized) {
      throw StateError(
          'ClassManager not initialized. Call initialize() first.');
    }

    final cropEmbedding = await _embedder.embedImage(cropImage);

    // Use optimized vector search in the database
    return await _db.findBestClass(
      queryEmbedding: cropEmbedding,
      classNames: classNames,
    );
  }


  /// Dispose of resources
  void dispose() {
    _embedder.dispose();
    _db.close();
  }
}
