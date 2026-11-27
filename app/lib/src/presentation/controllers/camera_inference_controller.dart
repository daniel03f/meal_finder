import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:meal_finder/src/services/audio_guidance.dart';
import 'package:meal_finder/src/services/class_manager.dart';
import 'package:meal_finder/src/services/database_service.dart';
import 'package:meal_finder/src/utils/image_utils.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import '../../utils/error_handler.dart';
import '../../models/models.dart';
import '../../services/model_manager.dart';

/// Controller that manages the state and business logic for camera inference
class CameraInferenceController extends ChangeNotifier {
  // Detection state
  int _detectionCount = 0;
  double _currentFps = 0.0;
  DateTime _lastDetectionProcessing = DateTime.now();
  bool _isProcessing = false;

  // Threshold state
  double _confidenceThreshold = 0.6;
  double _iouThreshold = 0.45;
  int _numItemsThreshold = 10;
  SliderType _activeSlider = SliderType.none;

  // Model state
  ModelType _selectedModel = ModelType.detect;
  bool _isModelLoading = false;
  String? _modelPath;
  String _loadingMessage = '';
  double _loadingProgress = 0.0;

  // Label selection state
  final List<String>? _selectedLabels;

  // Camera state
  double _currentZoomLevel = 1.0;
  CameraLensDirection _lensFacing = CameraLensDirection.front;
  bool _isFrontCamera = false;
  bool _isLandscape = false;

  // Inference timing
  static const int _defaultMaxFPS = 1;
  static const int _defaultInferenceFrequency = 1;
  static const int _defaultSkipFrames = 0;

  // Controllers
  final _yoloController = YOLOViewController();
  late final ModelManager _modelManager;
  late final ClassManager _classManager;
  final AudioGuidanceService _audioGuidanceService = AudioGuidanceService();

  // Performance optimization
  bool _isDisposed = false;
  Future<void>? _loadingFuture;

  // Getters
  int get detectionCount => _detectionCount;
  double get currentFps => _currentFps;
  double get confidenceThreshold => _confidenceThreshold;
  double get iouThreshold => _iouThreshold;
  int get numItemsThreshold => _numItemsThreshold;
  SliderType get activeSlider => _activeSlider;
  ModelType get selectedModel => _selectedModel;
  bool get isModelLoading => _isModelLoading;
  String? get modelPath => _modelPath;
  String get loadingMessage => _loadingMessage;
  double get loadingProgress => _loadingProgress;
  double get currentZoomLevel => _currentZoomLevel;
  bool get isFrontCamera => _isFrontCamera;
  bool get isLandscape => _isLandscape;
  CameraLensDirection get lensFacing => _lensFacing;
  YOLOViewController get yoloController => _yoloController;
  ClassManager get classManager => _classManager;
  AudioGuidanceService get audioGuidanceService => _audioGuidanceService;

  YOLOStreamingConfig get yoloStreamingConfig {
    final bool needsBalancedInference =
        _selectedLabels != null && _selectedLabels.isNotEmpty;

    return YOLOStreamingConfig.custom(
      includeOriginalImage: true,
      maxFPS: needsBalancedInference ? _defaultMaxFPS : 5,
      inferenceFrequency: needsBalancedInference ? _defaultInferenceFrequency : 5,
      skipFrames: _defaultSkipFrames,
    );
  }



  CameraInferenceController({List<String>? selectedLabels, DatabaseService? databaseService, ClassManager? classManager})
      : _selectedLabels = selectedLabels {
    _isFrontCamera = _lensFacing == CameraLensDirection.front;

    _modelManager = ModelManager(
      onloadingProgress: (progress) {
        _loadingProgress = progress;
        notifyListeners();
      },
      onStatusUpdate: (message) {
        _loadingMessage = message;
        notifyListeners();
      },
    );

    _classManager = classManager ?? ClassManager(databaseService ?? DatabaseService());
  }

  /// Initialize the controller
  Future<void> initialize() async {
    await _loadModelForPlatform();
    _yoloController.setThresholds(
      confidenceThreshold: _confidenceThreshold,
      iouThreshold: _iouThreshold,
      numItemsThreshold: _numItemsThreshold,
    );

    try {
      await _classManager.initialize();
      if (_classManager.isInitialized) {
        debugPrint('ClassManager initialized successfully');
      } else {
        debugPrint(
            'ClassManager initialization failed - classification disabled');
      }
    } catch (e) {
      debugPrint('Error initializing ClassManager: $e');
      debugPrint('Classification will be disabled');
    }
  }

  /// Handle detection results and calculate FPS
  Future<YOLOResult?> onDetectionResults(
      List<YOLOResult> results, Uint8List imageList, DateTime timestamp) async {
    if (_isDisposed) return null;

    if (_detectionCount != results.length) {
      _detectionCount = results.length;
      notifyListeners();
    }

    if (!_classManager.isInitialized) {
      debugPrint('ClassManager not initialized, skipping classification');
      return null;
    }

    final classificationStart = DateTime.now();
    final elapsed = classificationStart.difference(_lastDetectionProcessing).inMilliseconds;


    if (_selectedLabels != null &&
        _selectedLabels.isNotEmpty &&
        results.isNotEmpty &&
        (elapsed >= 5000 || !_isProcessing)) {
      _isProcessing = true;
      _lastDetectionProcessing = classificationStart;

      // Image List is a JPEG byte array — rotate from sensor to display orientation
      final img.Image? decodedImage = await compute(
          decodeAndRotate, [imageList, isFrontCamera , isLandscape]);

      if (decodedImage == null || _isDisposed) {
        _isProcessing = false;
        return null;
      }

      YOLOResult? bestObject =
          await processClassifications(results, decodedImage);

      final classificationProcessingTime =  DateTime.now().difference(classificationStart).inMilliseconds;
      debugPrint('Processing time for classification: ${classificationProcessingTime}ms');
      
      if (bestObject != null) {
        debugPrint('Most confident object is: $bestObject');

        if(classificationProcessingTime < 5000) {
          await audioGuidanceService.guideToObject(bestObject);
          _isProcessing = false;
          return bestObject;
        }
        else {
          debugPrint('Skipping audio guidance due to high processing time');
          _isProcessing = false;
          return null;
        }
      }
    }
    else {
      debugPrint(
          'Skipping classification - either no labels selected, no results, or still processing (${elapsed}ms elapsed)');
    }
    return null;
  }

  @visibleForTesting
  Future<YOLOResult?> processClassifications(
      List<YOLOResult> results, img.Image decodedImage) async {

    double highestConfidence = 0.0;
    YOLOResult? bestObject;

    final startTime = DateTime.now();

    for (YOLOResult result in results) {
      try {
        final now = DateTime.now();
        if (now.difference(startTime).inMilliseconds > 4800) {
          debugPrint('Classification taking too long, aborting remaining items');
          break;
        }
        img.Image crop = createCrop(decodedImage, result.normalizedBox);

        final classificationResult = await _classManager.classifyCrop(
          cropImage: crop,
          classNames: _selectedLabels ?? [],
        );

        debugPrint(
            'Classification result (for ${_selectedLabels?.join(', ')}): '
            '${classificationResult.predictedClass} '
            '(confidence: ${classificationResult.confidence.toStringAsFixed(2)})');

        if (highestConfidence < classificationResult.confidence && classificationResult.predictedClass != '') {
          highestConfidence = classificationResult.confidence;
          bestObject = YOLOResult(
            classIndex: result.classIndex,
            className: classificationResult.predictedClass!,
            confidence: classificationResult.confidence * result.confidence,
            boundingBox: result.boundingBox,
            normalizedBox: result.normalizedBox,
            mask: result.mask,
            keypoints: result.keypoints,
            keypointConfidences: result.keypointConfidences,
          );
          if (classificationResult.confidence >= 0.75) {
            break;
          }
        }
      } catch (e) {
        debugPrint('Error classifying/creating crop: $e');
      }
    }
    if(highestConfidence < 0.7  || bestObject == null) {
      debugPrint('No classification above confidence threshold');
      return null;
    }
    return bestObject;
  }

  /// Handle performance metrics
  void onPerformanceMetrics(double fps, double processingTimeMs) {
    if (_isDisposed) return;

    if ((_currentFps - fps).abs() > 0.1) {
      _currentFps = fps;
      notifyListeners();
    }
  }

  void onZoomChanged(double zoomLevel) {
    if (_isDisposed) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      notifyListeners();
    }
  }

  void toggleSlider(SliderType type) {
    if (_isDisposed) return;

    if (_activeSlider != type) {
      _activeSlider = _activeSlider == type ? SliderType.none : type;
      notifyListeners();
    }
  }

  void updateSliderValue(double value) {
    if (_isDisposed) return;

    bool changed = false;
    switch (_activeSlider) {
      case SliderType.numItems:
        final newValue = value.toInt();
        if (_numItemsThreshold != newValue) {
          _numItemsThreshold = newValue;
          _yoloController.setNumItemsThreshold(_numItemsThreshold);
          changed = true;
        }
        break;
      case SliderType.confidence:
        if ((_confidenceThreshold - value).abs() > 0.01) {
          _confidenceThreshold = value;
          _yoloController.setConfidenceThreshold(value);
          changed = true;
        }
        break;
      case SliderType.iou:
        if ((_iouThreshold - value).abs() > 0.01) {
          _iouThreshold = value;
          _yoloController.setIoUThreshold(value);
          changed = true;
        }
        break;
      default:
        break;
    }

    if (changed) {
      notifyListeners();
    }
  }

  void setZoomLevel(double zoomLevel) {
    if (_isDisposed) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      _yoloController.setZoomLevel(zoomLevel);
      notifyListeners();
    }
  }

  void setLensFacing(CameraLensDirection facing) {
    if (_isDisposed) return;

    if (_lensFacing != facing) {
      _lensFacing = facing;
      _isFrontCamera = facing == CameraLensDirection.front;

      _yoloController.switchCamera();

      if (_isFrontCamera) {
        _currentZoomLevel = 1.0;
      }

      notifyListeners();
    }
  }

  void setIsLandscape(bool landscape) {
    if (_isDisposed) return;
    _isLandscape = landscape;
  }

  void changeModel(ModelType model) {
    if (_isDisposed) return;

    if (!_isModelLoading && model != _selectedModel) {
      _selectedModel = model;
      _loadModelForPlatform();
    }
  }

  Future<void> _loadModelForPlatform() async {
    if (_isDisposed) return;

    if (_loadingFuture != null) {
      await _loadingFuture;
      return;
    }

    _loadingFuture = _performModelLoading();
    try {
      await _loadingFuture;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<void> _performModelLoading() async {
    if (_isDisposed) return;

    _isModelLoading = true;
    _loadingMessage = 'Loading ${_selectedModel.modelName} model...';
    _loadingProgress = 0.0;
    _detectionCount = 0;
    _currentFps = 0.0;
    notifyListeners();

    try {
      final modelPath = await _modelManager.getModelPath(_selectedModel);

      if (_isDisposed) return;

      if (modelPath == null) {
        throw Exception('Failed to load ${_selectedModel.modelName} model');
      }

      _modelPath = modelPath;
      _isModelLoading = false;
      _loadingMessage = '';
      _loadingProgress = 0.0;
      notifyListeners();
    } catch (e) {
      if (_isDisposed) return;

      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load model ${_selectedModel.modelName} for task ${_selectedModel.task.name}',
      );

      _isModelLoading = false;
      _loadingMessage = 'Failed to load model: ${error.message}';
      _loadingProgress = 0.0;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
