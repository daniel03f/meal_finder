import 'package:flutter/material.dart';
import '../utils/utils.dart';
import '../models/models.dart';

/// Manages YOLO model loading from bundled assets.
class ModelManager {
  /// Callback for download progress updates (0.0 to 1.0)
  final void Function(double progress)? onloadingProgress;

  /// Callback for status message updates
  final void Function(String message)? onStatusUpdate;

  /// Creates a new ModelManager instance
  ///
  /// [onloadingProgress] is called with progress updates during model downloads
  /// [onStatusUpdate] is called with status messages during model operations
  ModelManager({this.onloadingProgress, this.onStatusUpdate});

  /// Gets the local path for a bundled model asset.
  Future<String?> getModelPath(ModelType modelType) async {
    _updateStatus('Checking for ${modelType.modelName} model...');
    try {
      _updateStatus('Loading ${modelType.modelName} model...');
      final modelPath = await getAssetPath(
        'assets/ml/models/${modelType.modelName}.tflite',
      );
      onloadingProgress?.call(1.0);
      return modelPath;
    } catch (e) {
      debugPrint('Error loading model from assets: $e');
      return null;
    }
  }

  /// Updates the status message
  void _updateStatus(String message) => onStatusUpdate?.call(message);
}