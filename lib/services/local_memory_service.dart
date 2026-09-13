import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/models/sign_prediction_model.dart';

class LocalMemoryService extends ChangeNotifier {
  Database? _db;

  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'ishara_memory.db');
    _db = await openDatabase(dbPath, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE translations(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sequenceHash TEXT UNIQUE,
          signSequence TEXT,
          arabicText TEXT,
          confidence REAL,
          modelVersion TEXT,
          timestamp INTEGER,
          usageCount INTEGER DEFAULT 1,
          provider TEXT,
          featuresJson TEXT
        )
      ''');
      await db.execute('CREATE INDEX idx_sequenceHash ON translations(sequenceHash)');
      await db.execute('CREATE INDEX idx_signSequence ON translations(signSequence)');
    });
  }

  String _computeHash(List<SignPrediction> sequence) {
    final normalized = sequence.map((p) => '${p.label}:${p.confidence.toStringAsFixed(2)}').join('|');
    final bytes = utf8.encode(normalized);
    return md5.convert(bytes).toString();
  }

  String _normalizeSequence(List<SignPrediction> sequence) {
    return sequence.map((p) => p.label).join(' ');
  }

  String _toFeaturesJson(List<SignPrediction> sequence) {
    final list = sequence.map((p) => {
      'label': p.label,
      'confidence': p.confidence,
      'timestamp': p.timestamp.toIso8601String(),
      'handedness': p.handedness?.toString(),
    }).toList();
    return jsonEncode(list);
  }

  Future<String?> lookupSequence(List<SignPrediction> sequence) async {
    if (sequence.isEmpty || _db == null) return null;
    final hash = _computeHash(sequence);
    final results = await _db!.query(
      'translations',
      where: 'sequenceHash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    if (results.isNotEmpty) {
      final row = results.first;
      final confidence = (row['confidence'] as double?) ?? 0.0;
      if (confidence >= AppConstants.aiConfidenceThreshold) {
        await _db!.update(
          'translations',
          {'usageCount': (row['usageCount'] as int? ?? 1) + 1},
          where: 'id = ?',
          whereArgs: [row['id'] as int],
        );
        return row['arabicText'] as String?;
      }
    }
    return null;
  }

  Future<void> storeSequence(List<SignPrediction> sequence, String arabicText, {String? provider}) async {
    if (sequence.isEmpty || _db == null) return;
    final hash = _computeHash(sequence);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db!.insert(
      'translations',
      {
        'sequenceHash': hash,
        'signSequence': _normalizeSequence(sequence),
        'arabicText': arabicText,
        'confidence': 1.0,
        'modelVersion': 'local-memory-v1',
        'timestamp': now,
        'usageCount': 1,
        'provider': provider ?? 'local',
        'featuresJson': _toFeaturesJson(sequence),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
    super.dispose();
  }
}
