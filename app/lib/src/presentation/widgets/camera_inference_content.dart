import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';
import 'package:ultralytics_yolo/widgets/yolo_overlay.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import '../../utils/image_utils.dart';
import '../../utils/map_converter.dart';
import '../controllers/camera_inference_controller.dart';
import 'model_loading_overlay.dart';

/// Main content widget that handles the camera view and loading states
class CameraInferenceContent extends StatefulWidget {
  const CameraInferenceContent({
    super.key,
    required this.controller,
    this.rebuildKey = 0,
    @visibleForTesting this.yoloView,
  });

  final CameraInferenceController controller;
  final int rebuildKey;

  @visibleForTesting
  final Widget? yoloView;

  @override
  State<CameraInferenceContent> createState() => CameraInferenceContentState();
}

class CameraInferenceContentState extends State<CameraInferenceContent> {
  YOLOResult? _bestObject;

  /// Processes a raw streaming-data map examining detections, performance metrics, and the original image.
  /// Updates the best detection and performance metrics in the controller.
  Future<void> handleStreamingData(Map<String, dynamic> data) async {
    try {
      final rawDetections = data['detections'] as List<dynamic>?;

      List<YOLOResult> detections = rawDetections != null
          ? MapConverter.convertToYOLOResults(rawDetections)
          : <YOLOResult>[];

      final fps = data['fps'] as double? ?? 0.0;
      final processingTimeMs = data['processingTimeMs'] as double? ?? 0.0;
      final originalImage = data['originalImage'] as Uint8List?;
      final timestamp = data['timestamp'] is int
        ? DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int)
        : data['timestamp'] as DateTime? ?? DateTime.now();

      widget.controller.onPerformanceMetrics(fps, processingTimeMs);
      final bestObject = await widget.controller.onDetectionResults(
        detections,
        originalImage!,
        timestamp
      );

      if (mounted) {
        setState(() => _bestObject = bestObject);
      }
    } catch (e) {
      debugPrint('Error processing streaming data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.modelPath != null && !widget.controller.isModelLoading) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              widget.yoloView ??
                  YOLOView(
                    key: ValueKey(
                      'yolo_view_${widget.controller.modelPath}_${widget.controller.selectedModel.task.name}_${widget.rebuildKey}',
                    ),
                    controller: widget.controller.yoloController,
                    modelPath: widget.controller.modelPath!,
                    task: widget.controller.selectedModel.task,
                    streamingConfig: widget.controller.yoloStreamingConfig,
                    showOverlays: false,
                    onZoomChanged: widget.controller.onZoomChanged,
                    onStreamingData: (data) async {
                      await handleStreamingData(data);
                    },
                  ),
              if (_bestObject != null)
                Positioned.fill(
                  key: const ValueKey('best_object_overlay'),
                  child: YOLOOverlay(
                    detections: [
                      YOLOResult(
                        classIndex: _bestObject!.classIndex,
                        className: _bestObject!.className,
                        confidence: _bestObject!.confidence,
                        boundingBox: normalizedToScreenRect(
                          _bestObject!.normalizedBox,
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                        normalizedBox: _bestObject!.normalizedBox,
                        mask: _bestObject!.mask,
                        keypoints: _bestObject!.keypoints,
                        keypointConfidences: _bestObject!.keypointConfidences,
                      ),
                    ],
                    showConfidence: true,
                    showClassName: true,
                    theme: const YOLOOverlayTheme(
                      boundingBoxColor: Colors.green,
                    ),
                  ),
                ),
            ],
          );
        },
      );
    } else if (widget.controller.isModelLoading) {
      return ModelLoadingOverlay(
        loadingMessage: widget.controller.loadingMessage,
        loadingProgress: widget.controller.loadingProgress,
      );
    } else {
      return const Center(
        child: Text('No model loaded', style: TextStyle(color: Colors.white)),
      );
    }
  }
}
