import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _database;
  Future<Database>? _openingDatabase;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final pending = _openingDatabase;
    if (pending != null) return pending;

    final opening = _openDatabase();
    _openingDatabase = opening;
    try {
      final opened = await opening;
      _database = opened;
      return opened;
    } catch (_) {
      _openingDatabase = null;
      rethrow;
    }
  }

  Future<Database> _openDatabase() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, 'road_guard_annotator.db');
    return openDatabase(
      dbPath,
      version: 6,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createLegacyTables(db);
        await _createAnnotationsTable(db);
        await _createAppSettingsTable(db);
        await _seedAnnotationTypes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE markers ADD COLUMN elapsed_ns INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          try {
            await db.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_markers_event_sequence_unique '
              'ON markers(event_id, marker_sequence)',
            );
            await db.execute('DROP INDEX IF EXISTS idx_markers_event_sequence');
          } on DatabaseException {
            // Preserve pre-existing legacy rows if they contain duplicates.
          }
        }
        if (oldVersion < 4) {
          await _createAnnotationsTable(db);
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE event_types ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
          );
          final existingTypes = await db.query(
            'event_types',
            columns: ['label'],
            orderBy: "CASE label WHEN 'BUMP' THEN 0 WHEN 'POTHOLE' THEN 1 WHEN 'OTHER' THEN 2 ELSE 3 END, created_utc_ms ASC, label COLLATE NOCASE ASC",
          );
          for (var i = 0; i < existingTypes.length; i++) {
            await db.update(
              'event_types',
              {'sort_order': i},
              where: 'label = ?',
              whereArgs: [existingTypes[i]['label']],
            );
          }
          await _createAppSettingsTable(db);
        }
        if (oldVersion < 6) {
          await db.insert(
            'app_settings',
            {'setting_key': 'theme_mode', 'setting_value': 'dark'},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      },
    );
  }

  Future<void> _createLegacyTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE sessions (
        session_id TEXT PRIMARY KEY,
        trip_id TEXT NOT NULL,
        recording_id TEXT NOT NULL,
        annotator_id TEXT,
        device_id TEXT,
        start_mono_ns INTEGER NOT NULL,
        start_utc_ms INTEGER NOT NULL,
        timezone_offset_minutes INTEGER NOT NULL,
        end_mono_ns INTEGER,
        end_utc_ms INTEGER,
        status TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE event_types (
        label TEXT PRIMARY KEY,
        created_utc_ms INTEGER NOT NULL,
        is_custom INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE events (
        event_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        event_label TEXT NOT NULL,
        is_normal_segment INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        start_mono_ns INTEGER NOT NULL,
        start_utc_ms INTEGER NOT NULL,
        notes TEXT,
        FOREIGN KEY(session_id) REFERENCES sessions(session_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE markers (
        marker_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        event_label TEXT NOT NULL,
        marker_type TEXT NOT NULL,
        marker_meaning TEXT NOT NULL,
        marker_sequence INTEGER NOT NULL,
        t_mono_ns INTEGER NOT NULL,
        t_utc_epoch_ms INTEGER NOT NULL,
        timestamp_local TEXT NOT NULL,
        local_date TEXT NOT NULL,
        local_time TEXT NOT NULL,
        timestamp_utc_iso TEXT NOT NULL,
        elapsed_ns INTEGER NOT NULL,
        elapsed_ms INTEGER NOT NULL,
        elapsed_hms_ms TEXT NOT NULL,
        timezone_offset_minutes INTEGER NOT NULL,
        timezone_offset TEXT NOT NULL,
        annotator_id TEXT,
        device_id TEXT,
        latitude REAL,
        longitude REAL,
        gps_accuracy_m REAL,
        confidence TEXT,
        uncertainty_ms INTEGER,
        press_duration_ms INTEGER,
        notes TEXT,
        FOREIGN KEY(session_id) REFERENCES sessions(session_id),
        FOREIGN KEY(event_id) REFERENCES events(event_id),
        UNIQUE(event_id, marker_sequence)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_markers_session_time ON markers(session_id, t_mono_ns)',
    );
  }

  Future<void> _createAnnotationsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS annotations (
        annotation_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        annotation_name TEXT NOT NULL,
        t_mono_ns INTEGER NOT NULL,
        t_utc_epoch_ms INTEGER NOT NULL,
        timestamp_local TEXT NOT NULL,
        local_date TEXT NOT NULL,
        local_time TEXT NOT NULL,
        timestamp_utc_iso TEXT NOT NULL,
        elapsed_ns INTEGER NOT NULL,
        elapsed_ms INTEGER NOT NULL,
        elapsed_hms_ms TEXT NOT NULL,
        timezone_offset_minutes INTEGER NOT NULL,
        timezone_offset TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        gps_accuracy_m REAL,
        notes TEXT,
        FOREIGN KEY(session_id) REFERENCES sessions(session_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_annotations_session_time '
      'ON annotations(session_id, t_mono_ns)',
    );
  }

  Future<void> _createAppSettingsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
    await db.insert(
      'app_settings',
      {'setting_key': 'annotation_sort_mode', 'setting_value': 'manual'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      'app_settings',
      {'setting_key': 'theme_mode', 'setting_value': 'dark'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _seedAnnotationTypes(DatabaseExecutor db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    final defaults = ['BUMP', 'POTHOLE', 'OTHER'];
    for (var i = 0; i < defaults.length; i++) {
      batch.insert(
        'event_types',
        {
          'label': defaults[i],
          'created_utc_ms': now,
          'is_custom': 0,
          'sort_order': i,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> createSession(Map<String, Object?> values) async {
    final db = await database;
    await db.insert('sessions', values, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<List<Map<String, Object?>>> getRecentSessions({int limit = 20}) async {
    final db = await database;
    return db.query('sessions', orderBy: 'start_utc_ms DESC', limit: limit);
  }

  Future<Map<String, Object?>?> getSession(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateSessionTripName({
    required String sessionId,
    required String tripName,
  }) async {
    final cleanName = tripName.trim();
    if (cleanName.isEmpty) throw ArgumentError('Trip name cannot be empty.');
    final db = await database;
    final changed = await db.update(
      'sessions',
      {'trip_id': cleanName},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    if (changed != 1) throw StateError('Trip was not found.');
  }

  /// Deletes a saved trip and every row belonging to it in one transaction.
  /// Annotation button definitions are global and are deliberately preserved.
  Future<void> deleteSessionAndRecords(String sessionId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('markers', where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('events', where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('annotations', where: 'session_id = ?', whereArgs: [sessionId]);
      final deleted = await txn.delete(
        'sessions',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      if (deleted != 1) throw StateError('Trip was not found.');
    });
  }

  Future<Map<String, Object?>?> getActiveSession() async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'status = ?',
      whereArgs: ['ACTIVE'],
      orderBy: 'start_utc_ms DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> markSessionInterruptedByClockReset({
    required String sessionId,
    required int detectedUtcMs,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'events',
        {
          'status': 'INCOMPLETE',
          'notes': 'Session interrupted because the Android monotonic clock reset (device reboot).',
        },
        where: 'session_id = ? AND status = ?',
        whereArgs: [sessionId, 'ACTIVE'],
      );
      await txn.update(
        'sessions',
        {'status': 'INTERRUPTED_CLOCK_RESET', 'end_utc_ms': detectedUtcMs},
        where: 'session_id = ? AND status = ?',
        whereArgs: [sessionId, 'ACTIVE'],
      );
    });
  }

  Future<void> finishSession({
    required String sessionId,
    required int endMonoNs,
    required int endUtcMs,
  }) async {
    final db = await database;
    await db.update(
      'sessions',
      {
        'end_mono_ns': endMonoNs,
        'end_utc_ms': endUtcMs,
        'status': 'COMPLETED',
      },
      where: 'session_id = ? AND status = ?',
      whereArgs: [sessionId, 'ACTIVE'],
    );
  }

  Future<String> getAnnotationSortMode() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['annotation_sort_mode'],
      limit: 1,
    );
    if (rows.isEmpty) return 'manual';
    final value = rows.first['setting_value'] as String;
    const supported = {'manual', 'oldest', 'newest', 'alphabetical'};
    return supported.contains(value) ? value : 'manual';
  }

  Future<void> setAnnotationSortMode(String mode) async {
    const supported = {'manual', 'oldest', 'newest', 'alphabetical'};
    if (!supported.contains(mode)) {
      throw ArgumentError.value(mode, 'mode', 'Unsupported annotation sort mode.');
    }
    final db = await database;
    await db.insert(
      'app_settings',
      {'setting_key': 'annotation_sort_mode', 'setting_value': mode},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> getThemeMode() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['theme_mode'],
      limit: 1,
    );
    if (rows.isEmpty) return 'dark';
    final value = rows.first['setting_value'] as String;
    return value == 'light' ? 'light' : 'dark';
  }

  Future<void> setThemeMode(String mode) async {
    if (mode != 'light' && mode != 'dark') {
      throw ArgumentError.value(mode, 'mode', 'Theme must be light or dark.');
    }
    final db = await database;
    await db.insert(
      'app_settings',
      {'setting_key': 'theme_mode', 'setting_value': mode},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> getEventTypes({String sortMode = 'manual'}) async {
    final db = await database;
    final orderBy = switch (sortMode) {
      'oldest' => 'created_utc_ms ASC, sort_order ASC, label COLLATE NOCASE ASC',
      'newest' => 'created_utc_ms DESC, sort_order ASC, label COLLATE NOCASE ASC',
      'alphabetical' => 'label COLLATE NOCASE ASC',
      _ => 'sort_order ASC, created_utc_ms ASC, label COLLATE NOCASE ASC',
    };
    final rows = await db.query('event_types', orderBy: orderBy);
    return rows.map((row) => row['label'] as String).toList();
  }

  Future<void> addEventType(String label, int utcEpochMs) async {
    final cleanLabel = label.trim();
    if (cleanLabel.isEmpty) throw ArgumentError('Annotation name cannot be empty.');
    final db = await database;
    await db.transaction((txn) async {
      final duplicate = await txn.query(
        'event_types',
        columns: ['label'],
        where: 'label = ? COLLATE NOCASE',
        whereArgs: [cleanLabel],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('An annotation with this name already exists.');
      }
      final result = await txn.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order FROM event_types',
      );
      final nextOrder = (result.first['next_order'] as int?) ?? 0;
      await txn.insert('event_types', {
        'label': cleanLabel,
        'created_utc_ms': utcEpochMs,
        'is_custom': 1,
        'sort_order': nextOrder,
      });
    });
  }

  Future<void> reorderEventTypes(List<String> orderedLabels) async {
    final db = await database;
    await db.transaction((txn) async {
      final currentRows = await txn.query('event_types', columns: ['label']);
      final currentLabels = currentRows.map((row) => row['label'] as String).toSet();
      final requestedLabels = orderedLabels.toSet();
      if (orderedLabels.length != currentLabels.length ||
          requestedLabels.length != orderedLabels.length ||
          !requestedLabels.containsAll(currentLabels)) {
        throw StateError('The annotation button list changed. Refresh and try again.');
      }
      final batch = txn.batch();
      for (var i = 0; i < orderedLabels.length; i++) {
        batch.update(
          'event_types',
          {'sort_order': i},
          where: 'label = ?',
          whereArgs: [orderedLabels[i]],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> renameEventType({
    required String oldLabel,
    required String newLabel,
  }) async {
    final cleanLabel = newLabel.trim();
    if (cleanLabel.isEmpty) throw ArgumentError('Annotation name cannot be empty.');
    final db = await database;
    await db.transaction((txn) async {
      final duplicate = await txn.query(
        'event_types',
        columns: ['label'],
        where: 'label = ? COLLATE NOCASE AND label != ?',
        whereArgs: [cleanLabel, oldLabel],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('An annotation with this name already exists.');
      }
      final updated = await txn.update(
        'event_types',
        {'label': cleanLabel, 'is_custom': 1},
        where: 'label = ?',
        whereArgs: [oldLabel],
      );
      if (updated != 1) throw StateError('Annotation type no longer exists.');
    });
  }

  /// Deleting a button type does not delete historical annotation records.
  Future<void> deleteEventType(String label) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('event_types', where: 'label = ?', whereArgs: [label]);
      final remaining = await txn.query(
        'event_types',
        columns: ['label'],
        orderBy: 'sort_order ASC, created_utc_ms ASC, label COLLATE NOCASE ASC',
      );
      final batch = txn.batch();
      for (var i = 0; i < remaining.length; i++) {
        batch.update(
          'event_types',
          {'sort_order': i},
          where: 'label = ?',
          whereArgs: [remaining[i]['label']],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> insertAnnotation(Map<String, Object?> values) async {
    final db = await database;
    await db.insert(
      'annotations',
      values,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateAnnotationName({
    required String annotationId,
    required String annotationName,
  }) async {
    final cleanName = annotationName.trim();
    if (cleanName.isEmpty) throw ArgumentError('Annotation name cannot be empty.');
    final db = await database;
    final changed = await db.update(
      'annotations',
      {'annotation_name': cleanName},
      where: 'annotation_id = ?',
      whereArgs: [annotationId],
    );
    if (changed != 1) throw StateError('Annotation record was not found.');
  }

  Future<void> deleteAnnotation(String annotationId) async {
    final db = await database;
    final deleted = await db.delete(
      'annotations',
      where: 'annotation_id = ?',
      whereArgs: [annotationId],
    );
    if (deleted != 1) throw StateError('Annotation record was not found.');
  }

  Future<List<Map<String, Object?>>> getSessionAnnotations(
    String sessionId, {
    bool newestFirst = true,
  }) async {
    final db = await database;
    return db.query(
      'annotations',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: newestFirst ? 't_mono_ns DESC' : 't_mono_ns ASC',
    );
  }

  Future<List<Map<String, Object?>>> getAnnotationExportRows(
    String sessionId,
  ) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        a.*,
        s.trip_id AS trip_name,
        s.recording_id AS recording_id,
        s.annotator_id AS annotator_id,
        s.device_id AS device_id,
        s.start_mono_ns AS session_start_mono_ns,
        s.start_utc_ms AS session_start_utc_ms
      FROM annotations a
      INNER JOIN sessions s ON s.session_id = a.session_id
      WHERE a.session_id = ?
      ORDER BY a.t_mono_ns ASC
    ''', [sessionId]);
  }

  Future<int> countSessionAnnotations(String sessionId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM annotations WHERE session_id = ?',
      [sessionId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Legacy event/marker methods and tables are retained so an existing V1/V2
  // local database can be upgraded without deleting its earlier records.
  Future<void> createEventWithFirstMarker({
    required Map<String, Object?> eventValues,
    required Map<String, Object?> firstMarkerValues,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('events', eventValues);
      await txn.insert('markers', firstMarkerValues);
    });
  }

  Future<Map<String, Object?>?> getActiveEvent(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      'events',
      where: 'session_id = ? AND status = ?',
      whereArgs: [sessionId, 'ACTIVE'],
      orderBy: 'start_utc_ms DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> countMarkers(String eventId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM markers WHERE event_id = ?',
      [eventId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> insertMarkerAndMaybeComplete({
    required Map<String, Object?> markerValues,
    required String eventId,
    required bool completeEvent,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('markers', markerValues);
      if (completeEvent) {
        final updated = await txn.update(
          'events',
          {'status': 'COMPLETED'},
          where: 'event_id = ? AND status = ?',
          whereArgs: [eventId, 'ACTIVE'],
        );
        if (updated != 1) throw StateError('Event could not be completed.');
      }
    });
  }

  Future<void> cancelActiveEvent(String eventId, String reason) async {
    final db = await database;
    await db.update(
      'events',
      {'status': 'INCOMPLETE', 'notes': reason},
      where: 'event_id = ? AND status = ?',
      whereArgs: [eventId, 'ACTIVE'],
    );
  }

  Future<bool> undoLastMarker(String eventId) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'markers',
        where: 'event_id = ?',
        whereArgs: [eventId],
        orderBy: 'marker_sequence DESC',
        limit: 1,
      );
      if (rows.isEmpty) return false;
      await txn.delete(
        'markers',
        where: 'marker_id = ?',
        whereArgs: [rows.first['marker_id']],
      );
      final remaining = await txn.query(
        'markers',
        where: 'event_id = ?',
        whereArgs: [eventId],
      );
      if (remaining.isEmpty) {
        await txn.delete('events', where: 'event_id = ?', whereArgs: [eventId]);
      } else {
        await txn.update(
          'events',
          {'status': 'ACTIVE'},
          where: 'event_id = ?',
          whereArgs: [eventId],
        );
      }
      return true;
    });
  }

  Future<List<Map<String, Object?>>> getSessionEvents(String sessionId) async {
    final db = await database;
    return db.query(
      'events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'start_mono_ns DESC',
    );
  }

  Future<List<Map<String, Object?>>> getExportRows(String sessionId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT m.*, e.status AS event_status, e.is_normal_segment AS is_normal_segment,
        s.trip_id AS trip_id, s.recording_id AS recording_id,
        s.annotator_id AS session_annotator_id, s.device_id AS session_device_id,
        s.start_mono_ns AS session_start_mono_ns, s.start_utc_ms AS session_start_utc_ms
      FROM markers m
      INNER JOIN events e ON e.event_id = m.event_id
      INNER JOIN sessions s ON s.session_id = m.session_id
      WHERE m.session_id = ? ORDER BY m.t_mono_ns ASC
    ''', [sessionId]);
  }
}
