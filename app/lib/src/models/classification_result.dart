/// Result of a crop classification
class ClassificationResult {
  final String? predictedClass;
  final double confidence;

  ClassificationResult({
    this.predictedClass,
    required this.confidence,
  });

  factory ClassificationResult.fromJson(Map<String, dynamic> json) {
    return ClassificationResult(
      predictedClass: json['predicted_class'] as String?,
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'predicted_class': predictedClass,
    'confidence': confidence,
  };

  @override
  String toString() {
    return 'predictedClass: $predictedClass, confidence: $confidence';
  }
}
