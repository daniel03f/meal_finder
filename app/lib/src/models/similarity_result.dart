/// Result of a similarity comparison between crops
class SimilarityResult {
  final double similarity;
  final String? assignedClass;
  final int cropId;

  SimilarityResult({
    required this.similarity,
    this.assignedClass,
    required this.cropId,
  });

  factory SimilarityResult.fromJson(Map<String, dynamic> json) {
    return SimilarityResult(
      similarity: (json['similarity'] as num).toDouble(),
      assignedClass: json['assigned_class'] as String?,
      cropId: json['crop_id'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'similarity': similarity,
    'assigned_class': assignedClass,
    'crop_id': cropId,
  };
}
