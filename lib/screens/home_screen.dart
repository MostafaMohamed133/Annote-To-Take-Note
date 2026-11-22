import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/clock_snapshot.dart';
import '../services/clock_service.dart';
import '../services/annotation_order_service.dart';
import '../services/csv_export_service.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/time_format_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseService _db = DatabaseService.instance;
  final LocationService _location = LocationService();
  final Uuid _uuid = const Uuid();
  final TextEditingController _tripController = TextEditingController();

  Map<String, Object?>? _session;
  List<Map<String, Object?>> _annotations = [];
  List<Map<String, Object?>> _recentSessions = [];
  List<String> _annotationTypes = [];
  String _annotationSortMode = 'manual';
  bool _reorderingAnnotationTypes = false;
  bool _loading = true;
  bool _startingTrip = false;
  bool _endingTrip = false;
  int _pendingWrites = 0;
  bool _gpsAvailable = false;
  String? _startupNotice;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;

  bool get _hasSession => _session != null;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _initialize();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _location.stop();
    _tripController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final sortMode = await _db.getAnnotationSortMode();
      final labels = await _db.getEventTypes(sortMode: sortMode);
      final activeSession = await _db.getActiveSession();
      if (activeSession != null) {
        final currentClock = await _captureClock();
        final sessionStartMonoNs = activeSession['start_mono_ns'] as int;
        if (currentClock.monotonicNs < sessionStartMonoNs) {
          await _db.markSessionInterruptedByClockReset(
            sessionId: activeSession['session_id'] as String,
            detectedUtcMs: currentClock.utcEpochMs,
          );
          _startupNotice =
              'The phone restarted during the previous trip. Saved annotations are preserved; start a new trip for a new monotonic timeline.';
        } else {
          _session = activeSession;
          _tripController.text = activeSession['trip_id'] as String;
          await ClockService.setKeepScreenOn(true);
          _gpsAvailable = await _location.start();
          _annotations = await _db.getSessionAnnotations(
            activeSession['session_id'] as String,
          );
        }
      }
      final sessions = await _db.getRecentSessions();
      if (!mounted) return;
      setState(() {
        _annotationTypes = labels;
        _annotationSortMode = sortMode;
        _recentSessions = sessions;
        _loading = false;
      });
      if (_startupNotice != null) _message(_startupNotice!);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Initialization failed: $error');
    }
  }

  Future<ClockSnapshot> _captureClock() => ClockService.capture();

  void _message(String text) {
    if (!mounted) return;
    // Queue snackbar work after the current route/widget transition completes.
    // This avoids changing the root Overlay while a dialog is being removed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    });
  }

  Future<String?> _showAnnotationNameDialog({
    required String title,
    required String actionLabel,
    String initialName = '',
    String hintText = 'e.g. RAILWAY CROSSING',
    String fieldLabel = 'Annotation name',
  }) {
    return showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _AnnotationNameDialog(
        title: title,
        actionLabel: actionLabel,
        initialName: initialName,
        hintText: hintText,
        fieldLabel: fieldLabel,
      ),
    );
  }

  Future<void> _startTrip() async {
    final tripName = _tripController.text.trim();
    if (tripName.isEmpty) {
      _message('Enter the trip name first.');
      return;
    }
    setState(() => _startingTrip = true);
    try {
      final start = await _captureClock();
      final sessionId = _uuid.v4();
      final recordingId = 'REC_${_uuid.v4().substring(0, 8).toUpperCase()}';
      await _db.createSession({
        'session_id': sessionId,
        'trip_id': tripName,
        'recording_id': recordingId,
        'annotator_id': '',
        'device_id': '',
        'start_mono_ns': start.monotonicNs,
        'start_utc_ms': start.utcEpochMs,
        'timezone_offset_minutes': start.timezoneOffsetMinutes,
        'status': 'ACTIVE',
      });
      final session = await _db.getSession(sessionId);
      await ClockService.setKeepScreenOn(true);
      final gpsAvailable = await _location.start();
      if (!mounted) return;
      setState(() {
        _session = session;
        _annotations = [];
        _gpsAvailable = gpsAvailable;
      });
      _message('Trip started. Tap any annotation button to save a timestamp immediately.');
    } catch (error) {
      _message('Could not start trip: $error');
    } finally {
      if (mounted) setState(() => _startingTrip = false);
    }
  }

  Future<void> _addAnnotationType() async {
    final name = await _showAnnotationNameDialog(
      title: 'Add annotation button',
      actionLabel: 'Add button',
    );
    if (!mounted || name == null || name.trim().isEmpty) return;

    try {
      // Let the dialog route and its focus subtree finish deactivating before
      // mutating the page's dynamic button list.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final now = await _captureClock();
      await _db.addEventType(name, now.utcEpochMs);
      final labels = await _db.getEventTypes(sortMode: _annotationSortMode);
      if (!mounted) return;
      setState(() => _annotationTypes = labels);
      _message('Annotation button "$name" added.');
    } catch (error) {
      _message('Could not add annotation: $error');
    }
  }

  Future<void> _editAnnotationType(String oldName) async {
    final newName = await _showAnnotationNameDialog(
      title: 'Edit annotation name',
      actionLabel: 'Save',
      initialName: oldName,
      hintText: 'Enter annotation name',
    );
    if (!mounted || newName == null || newName.trim().isEmpty || newName == oldName) {
      return;
    }

    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _db.renameEventType(oldLabel: oldName, newLabel: newName);
      final labels = await _db.getEventTypes(sortMode: _annotationSortMode);
      if (!mounted) return;
      setState(() => _annotationTypes = labels);
      _message('Annotation button renamed. Previous records keep their original name.');
    } catch (error) {
      _message('Could not rename annotation: $error');
    }
  }

  Future<void> _deleteAnnotationType(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete annotation button?'),
        content: Text(
          '"$name" will be removed from the available buttons. Previously recorded rows will remain in the trip history and CSV files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete button'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.deleteEventType(name);
      await _refreshAnnotationTypes();
      _message('Button deleted. Previously recorded annotations were kept.');
    } catch (error) {
      _message('Could not delete annotation button: $error');
    }
  }

  Future<void> _refreshAnnotationTypes() async {
    final labels = await _db.getEventTypes(sortMode: _annotationSortMode);
    if (!mounted) return;
    setState(() => _annotationTypes = labels);
  }

  Future<void> _changeAnnotationSortMode(String mode) async {
    if (mode == _annotationSortMode) return;
    final previousMode = _annotationSortMode;
    setState(() => _annotationSortMode = mode);
    try {
      await _db.setAnnotationSortMode(mode);
      final labels = await _db.getEventTypes(sortMode: mode);
      if (!mounted) return;
      setState(() => _annotationTypes = labels);
      _message('Annotation buttons: ${_sortModeLabel(mode)}.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _annotationSortMode = previousMode);
      await _refreshAnnotationTypes();
      _message('Could not change button order: $error');
    }
  }

  String _sortModeLabel(String mode) {
    return switch (mode) {
      'oldest' => 'Oldest added first',
      'newest' => 'Newest added first',
      'alphabetical' => 'A–Z',
      _ => 'Manual order',
    };
  }

  Future<void> _reorderAnnotationType(
    String draggedName,
    String targetName, {
    bool placeAtEnd = false,
  }) async {
    if (_annotationSortMode != 'manual' ||
        _reorderingAnnotationTypes ||
        draggedName == targetName) {
      return;
    }
    final oldIndex = _annotationTypes.indexOf(draggedName);
    if (oldIndex < 0 || (!placeAtEnd && !_annotationTypes.contains(targetName))) {
      return;
    }

    final updated = placeAtEnd
        ? AnnotationOrderService.moveToEnd(
            current: _annotationTypes,
            draggedName: draggedName,
          )
        : AnnotationOrderService.moveBefore(
            current: _annotationTypes,
            draggedName: draggedName,
            targetName: targetName,
          );
    if (_sameAnnotationOrder(updated, _annotationTypes)) return;
    setState(() {
      _annotationTypes = updated;
      _reorderingAnnotationTypes = true;
    });

    try {
      await _db.reorderEventTypes(updated);
    } catch (error) {
      await _refreshAnnotationTypes();
      _message('Could not save button order: $error');
    } finally {
      if (mounted) setState(() => _reorderingAnnotationTypes = false);
    }
  }

  bool _sameAnnotationOrder(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }

  Widget _annotationTypeItem(String name, double width) {
    final button = _annotationButton(
      name,
      width: width,
      showDragHandle: _annotationSortMode == 'manual',
    );
    if (_annotationSortMode != 'manual') {
      return KeyedSubtree(
        key: ValueKey<String>('annotation-button-$name'),
        child: button,
      );
    }

    return DragTarget<String>(
      key: ValueKey<String>('annotation-drop-target-$name'),
      onWillAcceptWithDetails: (details) =>
          !_reorderingAnnotationTypes && details.data != name,
      onAcceptWithDetails: (details) =>
          _reorderAnnotationType(details.data, name),
      builder: (context, candidates, rejected) {
        final isTarget = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isTarget
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
          child: LongPressDraggable<String>(
            data: name,
            maxSimultaneousDrags: 1,
            feedback: Material(
              color: Colors.transparent,
              child: _annotationButton(name, width: width, showDragHandle: true),
            ),
            childWhenDragging: Opacity(opacity: 0.28, child: button),
            child: button,
          ),
        );
      },
    );
  }

  Widget _annotationEndDropTarget(double width) {
    return DragTarget<String>(
      key: const ValueKey<String>('annotation-end-drop-target'),
      onWillAcceptWithDetails: (details) =>
          !_reorderingAnnotationTypes && _annotationTypes.contains(details.data),
      onAcceptWithDetails: (details) => _reorderAnnotationType(
        details.data,
        '',
        placeAtEnd: true,
      ),
      builder: (context, candidates, rejected) => Container(
        width: width,
        height: 112,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: candidates.isNotEmpty
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: candidates.isNotEmpty ? 2 : 1,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.vertical_align_bottom_rounded),
            SizedBox(height: 4),
            Text('Drop here to move to end', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Future<void> _recordAnnotation(String name) async {
    final session = _session;
    if (session == null || _endingTrip) return;

    // Capture the clock as the first asynchronous operation after the tap.
    // Do not wait for GPS, SQLite, or file I/O before acquiring the timestamp.
    setState(() => _pendingWrites++);
    try {
      final snapshot = await _captureClock();
      final elapsedNs = snapshot.monotonicNs - (session['start_mono_ns'] as int);
      if (elapsedNs < 0) {
        throw StateError('Monotonic clock reset detected. End this trip and start a new one.');
      }
      final elapsedMs = elapsedNs ~/ 1000000;
      final formatted = TimeFormatService.format(
        utcEpochMs: snapshot.utcEpochMs,
        timezoneOffsetMinutes: snapshot.timezoneOffsetMinutes,
      );
      final location = _location.getFreshSnapshot();

      final record = <String, Object?>{
        'annotation_id': _uuid.v4(),
        'session_id': session['session_id'],
        'annotation_name': name,
        't_mono_ns': snapshot.monotonicNs,
        't_utc_epoch_ms': snapshot.utcEpochMs,
        'timestamp_local': formatted.localDateTime,
        'local_date': formatted.localDate,
        'local_time': formatted.localTime,
        'timestamp_utc_iso': formatted.utcIso,
        'elapsed_ns': elapsedNs,
        'elapsed_ms': elapsedMs,
        'elapsed_hms_ms': TimeFormatService.elapsedHmsMs(elapsedMs),
        'timezone_offset_minutes': snapshot.timezoneOffsetMinutes,
        'timezone_offset': formatted.timezoneOffset,
        'latitude': location?.latitude,
        'longitude': location?.longitude,
        'gps_accuracy_m': location?.accuracyMeters,
        'notes': null,
      };
      await _db.insertAnnotation(record);
      if (!mounted) return;
      // Merge the just-saved row locally instead of issuing a second SELECT.
      // This prevents a slower refresh from overwriting a newer list when
      // different annotation buttons are tapped rapidly in succession.
      setState(() {
        _annotations = [..._annotations, record]
          ..sort(
            (a, b) => (b['t_mono_ns'] as int).compareTo(a['t_mono_ns'] as int),
          );
      });
      _message('$name saved at ${formatted.localTime}.');
    } catch (error) {
      _message('Could not save "$name": $error');
    } finally {
      if (mounted) setState(() => _pendingWrites--);
    }
  }


  Future<void> _finishTrip() async {
    final session = _session;
    if (session == null || _endingTrip) return;
    if (_pendingWrites > 0) {
      _message('Please wait until the pending annotation saves are complete.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End this trip?'),
        content: Text(
          'All ${_annotations.length} saved annotations will be kept in the local database and exported to a CSV file for sharing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continue trip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('End trip'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _endingTrip = true);
    try {
      final end = await _captureClock();
      await _db.finishSession(
        sessionId: session['session_id'] as String,
        endMonoNs: end.monotonicNs,
        endUtcMs: end.utcEpochMs,
      );
      await ClockService.setKeepScreenOn(false);
      await _location.stop();
      final recent = await _db.getRecentSessions();
      if (!mounted) return;
      setState(() {
        _session = null;
        _annotations = [];
        _recentSessions = recent;
        _gpsAvailable = false;
      });
      _tripController.clear();
      _message('Trip ended. Preparing CSV export and share sheet.');
      await _exportSession(session['session_id'] as String);
    } catch (error) {
      _message('Could not finish trip: $error');
    } finally {
      if (mounted) setState(() => _endingTrip = false);
    }
  }

  Future<void> _exportSession(String sessionId) async {
    try {
      final session = await _db.getSession(sessionId);
      if (session == null) throw StateError('Trip session not found.');
      final rows = await _db.getAnnotationExportRows(sessionId);
      final csvBytes = CsvExportService.encode(rows);
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final exportDirectory = Directory('${documentsDirectory.path}/exports');
      if (!await exportDirectory.exists()) {
        await exportDirectory.create(recursive: true);
      }
      final safeTripName = _safeFileName(session['trip_id'] as String);
      final file = File(
        '${exportDirectory.path}/road_guard_${safeTripName}_${sessionId.substring(0, 8)}.csv',
      );
      await file.writeAsBytes(csvBytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Road Guard annotations – ${session['trip_id']}',
        text: 'Trip: ${session['trip_id']}\nAnnotations: ${rows.length}\n'
            'CSV includes full local date/time, UTC time, and monotonic nanoseconds for IMU synchronization.',
      );
    } catch (error) {
      _message('CSV was saved only if file creation completed. Export/share failed: $error');
    }
  }

  String _safeFileName(String input) {
    final safe = input
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-\u0600-\u06FF]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return safe.isEmpty ? 'trip' : safe;
  }

  Future<void> _editTripName(Map<String, Object?> session) async {
    final sessionId = session['session_id'] as String;
    final oldName = session['trip_id'] as String;
    final newName = await _showAnnotationNameDialog(
      title: 'Edit trip name',
      actionLabel: 'Save name',
      initialName: oldName,
      hintText: 'Enter trip name',
      fieldLabel: 'Trip name',
    );
    if (!mounted || newName == null || newName.trim().isEmpty || newName.trim() == oldName) {
      return;
    }
    try {
      await _db.updateSessionTripName(sessionId: sessionId, tripName: newName);
      final updatedSession = await _db.getSession(sessionId);
      final recent = await _db.getRecentSessions();
      if (!mounted) return;
      setState(() {
        _recentSessions = recent;
        if (_session?['session_id'] == sessionId && updatedSession != null) {
          _session = updatedSession;
        }
      });
      _message('Trip name updated. Its saved annotations and timestamps were preserved.');
    } catch (error) {
      _message('Could not update trip name: $error');
    }
  }

  Future<void> _deleteTripSession(Map<String, Object?> session) async {
    final sessionId = session['session_id'] as String;
    final tripName = session['trip_id'] as String;
    if (session['status'] == 'ACTIVE') {
      _message('End the active trip before deleting it.');
      return;
    }
    final count = await _db.countSessionAnnotations(sessionId);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete saved trip?'),
        content: Text(
          'Delete "$tripName" and all $count annotation records from this device? This cannot be undone. Previously shared CSV copies cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete trip and records'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.deleteSessionAndRecords(sessionId);
      var cleanupWarning = '';
      try {
        await _deleteLocalExportFiles(sessionId);
      } catch (error) {
        cleanupWarning = ' The saved local CSV copy could not be removed: $error';
      }
      final recent = await _db.getRecentSessions();
      if (!mounted) return;
      setState(() => _recentSessions = recent);
      _message('Trip "$tripName" and its database records were deleted.$cleanupWarning');
    } catch (error) {
      _message('Could not delete trip: $error');
    }
  }

  Future<void> _deleteLocalExportFiles(String sessionId) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final exportDirectory = Directory('${documentsDirectory.path}/exports');
    if (!await exportDirectory.exists()) return;
    final suffix = '_${sessionId.substring(0, 8)}.csv';
    await for (final entity in exportDirectory.list()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('road_guard_') &&
          entity.uri.pathSegments.last.endsWith(suffix)) {
        await entity.delete();
      }
    }
  }

  Future<void> _editRecordedAnnotation(Map<String, Object?> row) async {
    final annotationId = row['annotation_id'] as String;
    final oldName = row['annotation_name'] as String;
    final newName = await _showAnnotationNameDialog(
      title: 'Correct recorded annotation',
      actionLabel: 'Save correction',
      initialName: oldName,
      hintText: 'Enter the correct annotation label',
      fieldLabel: 'Correct annotation name',
    );
    if (!mounted || newName == null || newName.trim().isEmpty || newName.trim() == oldName) {
      return;
    }
    try {
      await _db.updateAnnotationName(
        annotationId: annotationId,
        annotationName: newName,
      );
      final sessionId = _session?['session_id'] as String?;
      if (sessionId != null) {
        final rows = await _db.getSessionAnnotations(sessionId);
        if (!mounted) return;
        setState(() => _annotations = rows);
      }
      _message('Annotation label corrected. Its original timestamps were preserved.');
    } catch (error) {
      _message('Could not correct annotation: $error');
    }
  }

  Future<void> _deleteRecordedAnnotation(Map<String, Object?> row) async {
    final annotationId = row['annotation_id'] as String;
    final name = row['annotation_name'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this annotation record?'),
        content: Text('Delete the saved "$name" tap and remove it from the trip CSV?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete record'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.deleteAnnotation(annotationId);
      if (!mounted) return;
      setState(() {
        _annotations.removeWhere((item) => item['annotation_id'] == annotationId);
      });
      _message('Annotation record deleted. The next CSV export will exclude it.');
    } catch (error) {
      _message('Could not delete annotation record: $error');
    }
  }

  Future<void> _showRecentTripDetails(Map<String, Object?> session) async {
    final count = await _db.countSessionAnnotations(session['session_id'] as String);
    if (!mounted) return;
    final start = TimeFormatService.format(
      utcEpochMs: session['start_utc_ms'] as int,
      timezoneOffsetMinutes: session['timezone_offset_minutes'] as int,
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(session['trip_id'] as String),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Started: ${start.localDateTime}'),
            Text('Status: ${session['status']}'),
            Text('Annotations: $count'),
            SelectableText('Session: ${session['session_id']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _exportSession(session['session_id'] as String);
            },
            icon: const Icon(Icons.ios_share),
            label: const Text('Export / Share CSV'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Road Guard Annotator'),
        actions: [
          IconButton(
            tooltip: widget.isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: widget.onToggleTheme,
            icon: Icon(widget.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
          ),
          if (_hasSession)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: _StatusPill(text: 'TRIP ACTIVE', color: Colors.green),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _hasSession
              ? _buildActiveTrip()
              : _buildTripSetup(),
    );
  }

  Widget _buildTripSetup() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_startupNotice != null) ...[
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_startupNotice!),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.route_rounded,
                  size: 36,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text('Start a new trip', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'Enter only the trip name. Annotation buttons can be added and managed after the trip starts.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _tripController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _startTrip(),
                  decoration: const InputDecoration(
                    labelText: 'Trip name',
                    hintText: 'e.g. Manfalut Trip 01',
                    prefixIcon: Icon(Icons.drive_file_rename_outline),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _startingTrip ? null : _startTrip,
                    icon: _startingTrip
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: const Text('START TRIP'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('Current device time', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        SelectableText(TimeFormatService.liveLocalTime(_now)),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text('Recent trips', style: Theme.of(context).textTheme.titleLarge),
            ),
            Text('${_recentSessions.length} saved', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        if (_recentSessions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Your completed trips will appear here.'),
            ),
          )
        else
          ..._recentSessions.map(_recentTripCard),
      ],
    );
  }

  Widget _recentTripCard(Map<String, Object?> session) {
    final tripName = session['trip_id'] as String;
    final start = TimeFormatService.format(
      utcEpochMs: session['start_utc_ms'] as int,
      timezoneOffsetMinutes: session['timezone_offset_minutes'] as int,
    );
    final status = session['status'] as String;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.route_outlined)),
        title: Text(tripName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${start.localDateTime}\n$status'),
        isThreeLine: true,
        onTap: () => _showRecentTripDetails(session),
        trailing: Wrap(
          spacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Edit trip name',
              onPressed: () => _editTripName(session),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Export and share CSV',
              onPressed: () => _exportSession(session['session_id'] as String),
              icon: const Icon(Icons.ios_share),
            ),
            IconButton(
              tooltip: 'Delete trip and its records',
              color: Theme.of(context).colorScheme.error,
              onPressed: () => _deleteTripSession(session),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTrip() {
    final session = _session!;
    final start = TimeFormatService.format(
      utcEpochMs: session['start_utc_ms'] as int,
      timezoneOffsetMinutes: session['timezone_offset_minutes'] as int,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.radio_button_checked, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        session['trip_id'] as String,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const _StatusPill(text: 'RECORDING', color: Colors.green),
                    IconButton(
                      tooltip: 'Edit trip name',
                      onPressed: () => _editTripName(session),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Started: ${start.localDateTime}', style: Theme.of(context).textTheme.bodySmall),
                Text('Now: ${TimeFormatService.liveLocalTime(_now)}', style: Theme.of(context).textTheme.bodySmall),
                Text('Recording ID: ${session['recording_id']}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      _gpsAvailable ? Icons.location_on : Icons.location_off,
                      size: 17,
                      color: _gpsAvailable ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _gpsAvailable ? 'GPS metadata available' : 'GPS unavailable (optional)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Text('${_annotations.length} saved', style: Theme.of(context).textTheme.labelLarge),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text('Annotation buttons', style: Theme.of(context).textTheme.titleLarge),
            ),
            PopupMenuButton<String>(
              tooltip: 'Arrange annotation buttons',
              initialValue: _annotationSortMode,
              onSelected: _changeAnnotationSortMode,
              icon: const Icon(Icons.sort),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'manual',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.drag_indicator),
                    title: Text('Manual order (drag to arrange)'),
                  ),
                ),
                PopupMenuItem(
                  value: 'oldest',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.history),
                    title: Text('Oldest added first'),
                  ),
                ),
                PopupMenuItem(
                  value: 'newest',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.update),
                    title: Text('Newest added first'),
                  ),
                ),
                PopupMenuItem(
                  value: 'alphabetical',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.sort_by_alpha),
                    title: Text('Alphabetical A–Z'),
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _addAnnotationType,
              icon: const Icon(Icons.add),
              label: const Text('ADD'),
            ),
          ],
        ),
        Text(
          _annotationSortMode == 'manual'
              ? 'Tap to record. Long-press and drag buttons to arrange them; use the edit or delete icons beside each button.'
              : 'Tap to record. Current order: ${_sortModeLabel(_annotationSortMode)}. Choose Manual order to arrange buttons yourself.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (_annotationTypes.isEmpty)
          OutlinedButton.icon(
            onPressed: _addAnnotationType,
            icon: const Icon(Icons.add),
            label: const Text('Add your first annotation button'),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ..._annotationTypes.map(
                    (name) => _annotationTypeItem(name, tileWidth),
                  ),
                  if (_annotationSortMode == 'manual')
                    _annotationEndDropTarget(tileWidth),
                ],
              );
            },
          ),
        if (_pendingWrites > 0) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Text('Saving $_pendingWrites annotation(s)…', style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _endingTrip || _pendingWrites > 0 ? null : _finishTrip,
            icon: _endingTrip
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.stop_circle_outlined),
            label: const Text('END TRIP & EXPORT CSV'),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text('Recorded annotations', style: Theme.of(context).textTheme.titleLarge),
            ),
            Text('${_annotations.length} rows', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        if (_annotations.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No annotations yet. Tap an annotation button above when the event occurs.'),
            ),
          )
        else
          ..._annotations.asMap().entries.map(
                (entry) => _annotationRecordCard(entry.value, _annotations.length - entry.key),
              ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _annotationButton(
    String name, {
    required double width,
    bool showDragHandle = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Edit $name',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(width: 34, height: 32),
                  padding: EdgeInsets.zero,
                  onPressed: () => _editAnnotationType(name),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: 'Delete $name',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(width: 34, height: 32),
                  padding: EdgeInsets.zero,
                  color: colors.error,
                  onPressed: () => _deleteAnnotationType(name),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
                if (showDragHandle)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                onPressed: _endingTrip ? null : () => _recordAnnotation(name),
                child: Text(
                  name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _annotationRecordCard(Map<String, Object?> row, int displayNumber) {
    final name = row['annotation_name'] as String;
    final date = row['local_date'] as String;
    final time = row['local_time'] as String;
    final tripName = _session?['trip_id'] as String? ?? '';
    return Card(
      child: ListTile(
        dense: false,
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Text('$displayNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$tripName\n$date  $time'),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Correct this annotation',
              visualDensity: VisualDensity.compact,
              onPressed: () => _editRecordedAnnotation(row),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete this annotation record',
              visualDensity: VisualDensity.compact,
              color: Theme.of(context).colorScheme.error,
              onPressed: () => _deleteRecordedAnnotation(row),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// Owns its text controller and focus lifecycle inside the dialog route.
/// Keeping these resources out of HomeScreen avoids disposing a controller
/// while the dialog's TextField is still being deactivated.
class _AnnotationNameDialog extends StatefulWidget {
  const _AnnotationNameDialog({
    required this.title,
    required this.actionLabel,
    required this.initialName,
    required this.hintText,
    required this.fieldLabel,
  });

  final String title;
  final String actionLabel;
  final String initialName;
  final String hintText;
  final String fieldLabel;

  @override
  State<_AnnotationNameDialog> createState() => _AnnotationNameDialogState();
}

class _AnnotationNameDialogState extends State<_AnnotationNameDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _focusNode = FocusNode(debugLabel: 'annotation-name-input');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _validationMessage = 'Please enter an annotation name.');
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context, rootNavigator: true).pop<String>(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: false,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        maxLength: 50,
        decoration: InputDecoration(
          labelText: widget.fieldLabel,
          hintText: widget.hintText,
          errorText: _validationMessage,
        ),
        onChanged: (_) {
          if (_validationMessage != null) {
            setState(() => _validationMessage = null);
          }
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

