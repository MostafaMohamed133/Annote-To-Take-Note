# Road Guard Annotator V1.2.0 – Changes

## UI and trip management
- Added edit action for active and completed trip names.
- Added delete action to recent trips. Deletion requires confirmation and removes the trip plus dependent annotations, markers and events in one SQLite transaction.
- Removes the local app-export CSV associated with the deleted session. Copies shared outside the app cannot be recalled.
- Moved END TRIP & EXPORT directly above the Recorded Annotations list.

## Annotation management
- Added edit and delete controls to each recorded annotation row.
- Editing changes the stored annotation label only; original UTC, local and monotonic timestamps are preserved.
- Deleting a recorded annotation removes it from the next CSV export.
- Annotation buttons are laid out in two columns on phone screens and retain manual drag sorting.

## Themes
- Added a persistent light/dark toggle in the top AppBar.
- Light palette: white surfaces with dark burgundy primary.
- Dark palette: near-black surfaces with purple primary.
- Added `theme_mode` setting and SQLite migration version 5 -> 6. Existing records and annotation ordering are preserved.

## Reliability
- Database opening is now memoized so app theme initialization and screen initialization cannot race to open two connections.
- Trip deletion is transactional and deletes child rows in FK-safe order.

## Time audit
- No timestamp-generation behavior was changed.
- Both wall-clock UTC (`t_utc_epoch_ms`) and monotonic (`t_mono_ns`) are stored.
- `time` remains UTC epoch nanoseconds-shaped but only millisecond precision; `t_mono_ns` remains the IMU synchronization key.

## Validation note
This source bundle was structurally reviewed, XML/YAML checked, and database operations were checked with SQLite in the build environment. Flutter SDK was not available here, so `flutter analyze`, `flutter test`, and Android APK build must be run on the user's configured machine before field collection.

# Road Guard Annotator V1.2.1 – Analyzer Fix

## Fix
- Removed an unreachable `return _database!;` after `_openDatabase()` had already returned the `openDatabase(...)` Future.
- `_openDatabase()` continues to return the `Database` produced by `openDatabase(...)`; the `database` getter remains responsible for caching the opened connection in `_database`.
- Bumped the app package version from `1.2.0+6` to `1.2.1+7`. The SQLite schema version remains 6; no database migration is required.

## Validation
- Confirmed the unreachable statement is no longer present and the method still returns `openDatabase(...)`.
- Archive and source structure are checked in this environment. Flutter/Dart SDK is not installed here, so `flutter analyze`, `flutter test`, and Android build must still be run on the target development machine.
