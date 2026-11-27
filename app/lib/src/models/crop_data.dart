import 'dart:typed_data';

/// Data model for a crop with its embedding and class assignment
class CropData {
  final int id;
  final List<double> embedding;
  final String? assignedClass;

  CropData({
    required this.id,
    required this.embedding,
    this.assignedClass,
  });

  factory CropData.fromMap(Map<String, dynamic> map) {
    // Convert blob bytes to List<double>
    List<double> embedding = [];
    if (map['embedding'] != null) {
      final bytes = map['embedding'] as List<int>;
      // Assuming Float32 (4 bytes per float)
      for (int i = 0; i < bytes.length; i += 4) {
        final buffer = bytes.sublist(i, i + 4);
        final byteData = ByteData.sublistView(Uint8List.fromList(buffer));
        embedding.add(byteData.getFloat32(0, Endian.little));
      }
    }

    return CropData(
      id: map['id'] as int,
      embedding: embedding,
      assignedClass: map['assigned_class'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    // Convert List<double> to bytes for storage
    final buffer = Float32List.fromList(embedding);
    final bytes = buffer.buffer.asUint8List();

    return {
      'id': id,
      'embedding': bytes,
      'assigned_class': assignedClass,
    };
  }
}
