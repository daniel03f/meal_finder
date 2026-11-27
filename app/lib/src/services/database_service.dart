import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_vector/sqlite_vector.dart';
import '../models/classification_result.dart';
import '../models/crop_data.dart';

/// Message types for isolate communication
enum _IsolateCommand { findBestClass, close }

/// Request sent to the background isolate
class _IsolateRequest {
  final _IsolateCommand command;
  final SendPort replyPort;
  final Uint8List? queryBlob;
  final List<String>? classNames;
  final int? limitPerClass;

  _IsolateRequest({
    required this.command,
    required this.replyPort,
    this.queryBlob,
    this.classNames,
    this.limitPerClass,
  });
}

/// Response from the background isolate
class _IsolateResponse {
  final String? predictedClass;
  final double confidence;
  final String? error;

  _IsolateResponse({this.predictedClass, this.confidence = 0.0, this.error});
}

/// Manages the SQLite database for classes and embeddings.
/// Uses sqlite_vector extension for optimized vector similarity search.
/// Heavy vector queries run in a persistent background isolate to keep the UI responsive.
class DatabaseService {
  Database? _database;
  final String _dbName = 'class_embeddings.sqlite';

  // Background isolate for vector search
  Isolate? _vectorIsolate;
  SendPort? _vectorSendPort;
  Completer<void>? _vectorIsolateReady;

  /// Get the database instance, creating it if necessary
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize the database with sqlite_vector extension
  Future<Database> _initDatabase() async {
    try {
      sqlite3.loadSqliteVectorExtension();

      // Get the database path
      final directory = await getApplicationDocumentsDirectory();
      final path = join(directory.path, _dbName);

      // Copy from assets if not present
      if (!File(path).existsSync()) {
        ByteData data = await rootBundle.load('assets/db/$_dbName');
        List<int> bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }

      // Open main-isolate DB (for lightweight queries)
      final db = sqlite3.open(path);

      // Spawn persistent background isolate in the background
      _vectorIsolateReady = Completer<void>();
      _spawnVectorIsolate(path).then((_) {
        _vectorIsolateReady?.complete();
      }).catchError((e) {
        debugPrint('Vector isolate spawn failed: $e');
        if (_vectorIsolateReady != null && !_vectorIsolateReady!.isCompleted) {
          _vectorIsolateReady!.completeError(e);
        }
      });

      return db;
    } catch (e) {
      debugPrint('Error initializing database: $e');
      throw Exception('Failed to initialize database: $e');
    }
  }

  /// Spawn a persistent background isolate that holds its own DB connection
  /// with vector extension loaded and quantized data preloaded.
  Future<void> _spawnVectorIsolate(String dbPath) async {
    final receivePort = ReceivePort();
    _vectorIsolate = await Isolate.spawn(
      _vectorIsolateEntry,
      [receivePort.sendPort, dbPath],
    );

    final initResult = await receivePort.first;
    if (initResult is SendPort) {
      _vectorSendPort = initResult;
    } else {
      throw Exception('Failed to start vector isolate: $initResult');
    }
  }

  /// Entry point for the persistent background isolate.
  /// Opens its own DB, loads vector extension, preloads quantized data,
  /// then listens for query requests.
  static void _vectorIsolateEntry(List<dynamic> args) {
    final mainSendPort = args[0] as SendPort;
    final dbPath = args[1] as String;

    Database db;
    try {
      sqlite3.loadSqliteVectorExtension();
      db = sqlite3.open(dbPath);
      db.execute(
          "SELECT vector_init('embedding_class', 'embedding', 'type=FLOAT32,dimension=384,distance=COSINE')");
      db.execute("SELECT vector_quantize('embedding_class', 'embedding')");
      db.execute("SELECT vector_quantize_preload('embedding_class', 'embedding')");
    } catch (e) {
      mainSendPort.send('init_error: $e');
      return;
    }

    // Send our ReceivePort's SendPort back so the main isolate can talk to us
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is _IsolateRequest) {
        switch (message.command) {
          case _IsolateCommand.findBestClass:
            try {
              final classNames = message.classNames!;
              final queryBlob = message.queryBlob!;
              final limitPerClass = message.limitPerClass ?? 10;
              final placeholders =
                  List.filled(classNames.length, '?').join(',');

              // Search for the best matching class using quantized vector scan and average distance per class
              final results = db.select('''
                SELECT assigned_class, AVG(distance) AS avg_distance
                FROM (
                  SELECT ec.class_name AS assigned_class, v.distance,
                  ROW_NUMBER() OVER (PARTITION BY ec.class_name ORDER BY v.distance) AS rn
                  FROM embedding_class AS ec
                  JOIN vector_quantize_scan('embedding_class', 'embedding', ?) AS v ON ec.id = v.rowid
                  WHERE ec.class_name IN ($placeholders)
                    AND ec.class_name != 'unassigned'
                ) sub
                WHERE rn <= ?
                GROUP BY assigned_class
                ORDER BY avg_distance
                LIMIT 1
              ''', [queryBlob, ...classNames, limitPerClass]);

              if (results.isEmpty) {
                message.replyPort.send(_IsolateResponse(confidence: 0.0));
                return;
              }

              final row = results.first;
              final bestClass = row['assigned_class'] as String;
              final avgDistance = (row['avg_distance'] as double);
              final confidence = (2.0 - avgDistance) / 2.0;

              message.replyPort.send(_IsolateResponse(
                predictedClass: bestClass,
                confidence: confidence,
              ));
            } catch (e) {
              message.replyPort
                  .send(_IsolateResponse(error: e.toString()));
            }
            break;

          case _IsolateCommand.close:
            db.close();
            message.replyPort.send(_IsolateResponse(confidence: 0.0));
            receivePort.close();
            break;
        }
      }
    });
  }

  /// Get all classes that have embeddings
  Future<List<String>> getAllClasses() async {
    final db = await database;
    final results = db.select('''
      SELECT DISTINCT cl.name
      FROM classes cl
      JOIN embedding_class ec ON ec.class_name = cl.name
      WHERE ec.embedding IS NOT NULL
      ORDER BY cl.name
    ''');

    return results.map((row) => row['name'] as String).toList();
  }

  /// Get all embeddings assigned to specified classes
  Future<List<CropData>> getClassCrops(List<String> classNames) async {
    final db = await database;
    final placeholders = List.filled(classNames.length, '?').join(',');
    final results = db.select('''
      SELECT ec.id, ec.embedding, ec.class_name AS assigned_class
      FROM embedding_class ec
      WHERE ec.class_name IN ($placeholders) AND ec.embedding IS NOT NULL
    ''', classNames);

    return results.map((row) => _convertRowToCropData(row)).toList();
  }

  /// Get all embeddings with class assignments
  Future<List<CropData>> getEmbeddedClassCrops() async {
    final db = await database;
    final results = db.select('''
      SELECT ec.id, ec.embedding, ec.class_name AS assigned_class
      FROM embedding_class ec
      WHERE ec.class_name IS NOT NULL AND ec.embedding IS NOT NULL
    ''');

    return results.map((row) => _convertRowToCropData(row)).toList();
  }

  /// Find the best matching class using vector similarity search.
  ///
  /// Runs on a persistent background isolate to avoid blocking the UI.
  /// Uses quantized vector scan for optimized cosine distance
  /// computation and returns the class with the lowest average distance to the query embedding.
  /// Optionally limits the number of embeddings per class to consider (default: 2).
  Future<ClassificationResult> findBestClass({
    required List<double> queryEmbedding,
    required List<String> classNames,
    int limitPerClass = 2,
  }) async {
    if (classNames.isEmpty || queryEmbedding.isEmpty) {
      return ClassificationResult(predictedClass: '', confidence: 0.0);
    }

    await database;
    if (_vectorIsolateReady != null) {
      try {
        await _vectorIsolateReady!.future;
      } catch (e) {
        debugPrint('Vector isolate failed during startup: $e');
        return ClassificationResult(predictedClass: '', confidence: 0.0);
      }
    }

    if (_vectorSendPort == null) {
      debugPrint('Vector isolate not available, cannot perform search');
      return ClassificationResult(predictedClass: '', confidence: 0.0);
    }

    // Convert embedding to Float32 BLOB
    final queryBlob = Float32List.fromList(
      queryEmbedding.map((e) => e.toDouble()).toList(),
    ).buffer.asUint8List();

    final responsePort = ReceivePort();
    _vectorSendPort!.send(_IsolateRequest(
      command: _IsolateCommand.findBestClass,
      replyPort: responsePort.sendPort,
      queryBlob: queryBlob,
      classNames: classNames,
      limitPerClass: limitPerClass,
    ));

    final response = await responsePort.first as _IsolateResponse;

    if (response.error != null) {
      debugPrint('Vector search error: ${response.error}');
      return ClassificationResult(predictedClass: '', confidence: 0.0);
    }

    return ClassificationResult(
      predictedClass: response.predictedClass ?? '',
      confidence: response.confidence,
    );
  }

  /// Convert database row to CropData object
  CropData _convertRowToCropData(Row row) {
    List<double> embedding = [];

    if (row['embedding'] != null) {
      // The embedding is stored as a BLOB in the database
      final bytes = row['embedding'] as Uint8List;
      // Convert bytes to Float32 array
      final byteData = ByteData.sublistView(bytes);
      for (int i = 0; i < bytes.length; i += 4) {
        embedding.add(byteData.getFloat32(i, Endian.little));
      }
    }

    return CropData(
      id: row['id'] as int,
      embedding: embedding,
      assignedClass: row['assigned_class'] as String?,
    );
  }

  /// Close the database connection and shutdown the background isolate
  Future<void> close() async {
    if (_vectorSendPort != null) {
      final responsePort = ReceivePort();
      _vectorSendPort!.send(_IsolateRequest(
        command: _IsolateCommand.close,
        replyPort: responsePort.sendPort,
      ));
      await responsePort.first;
    }
    _vectorIsolate?.kill(priority: Isolate.immediate);
    _vectorIsolate = null;
    _vectorSendPort = null;
    _vectorIsolateReady = null;

    _database?.close();
    _database = null;
  }
}
