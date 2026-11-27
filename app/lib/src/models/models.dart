import 'package:ultralytics_yolo/models/yolo_task.dart';

enum ModelType {
  detect('yolo11s_sku110k_best_float16', YOLOTask.detect);

  final String modelName;

  final YOLOTask task;

  const ModelType(this.modelName, this.task);
}

enum SliderType { none, numItems, confidence, iou }