# Road Guard Annotator

**Version:** `1.2.1+7`  
**Platform:** Android  
**Framework:** Flutter / Dart with a small native Kotlin bridge  
**Purpose:** Offline, timestamped manual annotation for Road Guard road-data collection.

Road Guard Annotator is a companion data-collection app for recording manually observed road events during a trip. It lets an annotator create a trip, tap customizable annotation buttons as events are observed, review or correct individual records, and export the trip's annotations to CSV.

The app records both Android monotonic time and wall-clock time. The monotonic timestamp is intended for synchronization with IMU streams captured on the **same Android device and using the same elapsed-realtime time base**. UTC and local date/time fields make records easier to inspect and audit.

> **Important scope note:** The current `1.2.1` UI records **one timestamped row per button tap** (`MANUAL_BUTTON_TAP`). It does not currently guide the user through a three-marker `START → FRONT_AXLE_PASSED/PEAK → REAR_AXLE_PASSED/END` event workflow, and it does not record accelerometer or gyroscope samples itself. Sensor data must be recorded separately (for example, with Sensor Logger) and synchronized using the monotonic time fields.

---

## Features

### Trip/session management

- Start a trip by entering its name.
- Generate a unique internal session ID and recording ID automatically.
- Keep the screen awake while a trip is active.
- View recent trips and their status, start time, and annotation count.
- Edit a trip name without changing its saved annotation timestamps.
- Export/share a previous trip's CSV again.
- Delete a completed or interrupted trip after confirmation. Its local database records and the app's corresponding local CSV export are removed. Copies already shared outside the app cannot be recalled.

### Annotation buttons

- Built-in buttons: `BUMP`, `POTHOLE`, and `OTHER`.
- Add custom annotation buttons using names chosen by the user.
- Edit or delete annotation button definitions.
- Arrange buttons manually by drag-and-drop, or sort by oldest added, newest added, or alphabetical order.
- Display two annotation buttons per row on a phone-sized screen.
- A tap records a new annotation immediately; rapid taps on different buttons are stored as separate records.
- Review the recorded list and edit the label or delete an individual record. Editing a record preserves its original timestamps; deleting it removes it from the next export.

### Time, location, and export

- Capture Android monotonic nanoseconds using `SystemClock.elapsedRealtimeNanos()`.
- Capture UTC epoch milliseconds using `System.currentTimeMillis()` in the same native clock-snapshot call.
- Store local date, local time with millisecond display precision, UTC ISO-8601 time, timezone offset, and elapsed time from trip start.
- Optionally attach a recent GPS position and its reported accuracy when location permission and location services are available.
- Save annotations locally in SQLite as they are recorded.
- Export one UTF-8 CSV per trip and open the Android share sheet.
- Keep the first four CSV columns compatible in name/order with the supplied Sensor Logger annotation format.
- Save the selected light/dark theme and annotation-button ordering locally.

### Appearance

- **Dark mode:** near-black surfaces with purple accents.
- **Light mode:** white surfaces with dark burgundy accents.
- Theme preference persists across app restarts.

---

## What this app does not do

- It does not record accelerometer or gyroscope streams.
- It does not run the Random Forest model or perform automatic bump/pothole detection.
- It does not automatically establish a verified physical event boundary or identify the true IMU signal peak.
- It does not upload sessions to a server; data is stored locally and shared only when the user exports/shares it.
- The generated `recording_id` is an app-side identifier. Do not assume it is automatically the same ID used by another sensor-recording app.

Road Guard Annotator is a **manual annotation companion**, not the complete Road Guard detection application.

---

## Time model and IMU synchronization

The Android native bridge (`MainActivity.kt`) captures the following values for each annotation:

| CSV field | Source | Meaning | Recommended use |
|---|---|---|---|
| `t_mono_ns` | `SystemClock.elapsedRealtimeNanos()` | Android monotonic timestamp in nanoseconds | Primary key for joining to compatible IMU `SensorEvent.timestamp` values from the same device/time base |
| `t_utc_epoch_ms` | `System.currentTimeMillis()` | UTC Unix epoch in milliseconds | Wall-clock reference and conversion to UTC/local date-time |
| `timestamp_utc_iso` | Derived from UTC epoch milliseconds | ISO-8601 UTC timestamp | Human-readable UTC reference |
| `timestamp_local` | UTC time plus captured timezone offset | Local date/time plus UTC offset | Human-readable local reference |
| `elapsed_ns` | `t_mono_ns - session_start_mono_ns` | Monotonic elapsed time since trip start | Relative position within the trip |
| `seconds_elapsed` | Derived from `elapsed_ns` | Elapsed seconds since trip start | Compatibility with the earlier annotation CSV layout |
| `time` | `t_utc_epoch_ms × 1,000,000` | UTC epoch value written in a nanosecond-shaped column | Legacy compatibility only; **effective precision is milliseconds**, not true nanoseconds |

### Important synchronization rules

1. Use `t_mono_ns` to align annotations with accelerometer/gyroscope samples, **only after confirming that the sensor logger uses the same Android elapsed-realtime time base on the same phone**.
2. Do not directly compare UTC timestamps with monotonic timestamps. They have different origins and meanings.
3. `t_utc_epoch_ms` and the formatted date/time fields have millisecond resolution. `t_mono_ns` is the nanosecond-resolution monotonic value.
4. `seconds_elapsed` is measured from the trip/session start using the monotonic clock, not calculated from wall-clock time.
5. The legacy `millisecond_press_duration` column is exported as empty because this app records tap timestamps, not the physical event duration or button-hold duration.
6. A monotonic clock resets after a device reboot. The app detects a reset against an active session and marks that session as interrupted rather than treating the restarted clock as a continuous timeline.

**Field validation is required before collecting a large dataset:** record a short test on the target phone, export both files, and verify that annotation `t_mono_ns` values align with the sensor file's monotonic timestamps.

---

## CSV format

The exported file is UTF-8 CSV with a byte-order mark for spreadsheet compatibility. Rows are sorted by `t_mono_ns` in ascending order (recording order), regardless of the visual order of annotation buttons or the order in which the list is displayed.

The current export includes these columns:

```text
time
seconds_elapsed
text
millisecond_press_duration
session_id
trip_name
recording_id
annotation_id
annotation_name
annotation_type
t_mono_ns
t_utc_epoch_ms
timestamp_local
local_date
local_time
timestamp_utc_iso
elapsed_ns
elapsed_ms
elapsed_hms_ms
timezone_offset_minutes
timezone_offset
annotator_id
device_id
latitude
longitude
gps_accuracy_m
notes
session_start_mono_ns
session_start_utc_ms
elapsed_origin
wall_clock_resolution_ms
```

### Example row interpretation

- `text` and `annotation_name`: the button label at the time of the tap.
- `annotation_id`: unique identifier for that recorded tap.
- `annotation_type`: `MANUAL_BUTTON_TAP`.
- `t_mono_ns`: primary monotonic timestamp for sensor synchronization.
- `local_date`: `YYYY-MM-DD`.
- `local_time`: `HH:mm:ss.SSS`.
- `timestamp_local`: local date/time including the UTC offset, for example `2026-11-22 21:30:15.235 +02:00`.
- `timestamp_utc_iso`: UTC ISO timestamp, for example `2026-11-22T19:30:15.235Z`.
- `latitude`, `longitude`, `gps_accuracy_m`: optional location metadata; empty if no sufficiently recent position is available.

All CSV cells are quoted and escaped. Keep the original CSV for analysis; spreadsheet applications may round long integer timestamps if they interpret them as numeric cells.

---

## Technology stack

- **Flutter / Dart:** UI and application logic.
- **Kotlin / Android:** native monotonic and UTC clock snapshot, plus keep-screen-on control.
- **SQLite (`sqflite`):** local trip, annotation, button-definition, and app-setting storage.
- **Geolocator:** optional recent GPS position and accuracy.
- **`share_plus`:** Android share sheet for CSV export.
- **UUID:** unique IDs for sessions, generated recording IDs, and annotation records.
- **Path Provider:** app-private export-file location.

### Main source structure

```text
road_guard_annotator/
├── android/                      # Android project and Kotlin bridge
├── lib/
│   ├── main.dart                 # App entry point, themes, theme persistence
│   ├── models/
│   │   └── clock_snapshot.dart   # Native clock snapshot model
│   ├── screens/
│   │   └── home_screen.dart      # Trips, annotation buttons, recorded list
│   └── services/
│       ├── annotation_order_service.dart
│       ├── clock_service.dart
│       ├── csv_export_service.dart
│       ├── database_service.dart
│       ├── location_service.dart
│       └── time_format_service.dart
├── test/                         # Flutter unit tests
├── examples/                     # Example CSV
├── docs/                         # Troubleshooting notes
├── tools/                         # Diagnostic scripts
├── pubspec.yaml
└── README.md
```

---

## Requirements

The project configuration in this source bundle targets:

- Flutter **3.35.x** (or a compatible Flutter version).
- Dart **3.9.x** (the `pubspec.yaml` constraint is `>=3.7.0 <4.0.0`).
- Android SDK Platform **36** for the configured `compileSdk`.
- Android Gradle Plugin **8.10.1**.
- Gradle Wrapper **8.12**.
- Kotlin Android plugin **2.1.0**.
- Java/JDK **17** for the configured Android compile target.
- An Android phone or emulator. For field annotation, a physical phone is recommended.

Use the versions installed in your local Flutter/Android environment and check `flutter doctor` if a build prerequisite is missing.

---

## Setup and run (Windows PowerShell)

1. Extract the project ZIP.
2. Open PowerShell in the folder that contains `pubspec.yaml`.
3. Check the Flutter and Android toolchains:

```powershell
flutter --version
flutter doctor -v
flutter devices
```

4. Resolve packages and run static analysis/tests:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
```

5. Run on the connected Android phone (replace the ID with the one shown by `flutter devices`):

```powershell
flutter run -d RFCWC1GD4QX
```

6. Build a release APK:

```powershell
flutter build apk --release
```

The APK is normally created at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

### ADB on Windows

If PowerShell says `adb` is not recognized, use the Android SDK Platform Tools executable directly:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices -l
```

You can add this directory to your user `PATH` if you want to run `adb` without the full path:

```text
%LOCALAPPDATA%\Android\Sdk\platform-tools
```

---

## Data storage and privacy

- Trip and annotation records are stored in the app's local SQLite database.
- CSV exports are written to the app's private `exports` directory before the Android share sheet is opened.
- GPS is optional. The app requests location permission when available and attaches a recent cached position (up to the service's freshness limit) to a tap. GPS is metadata, not the annotation timestamp source.
- There is no sign-in, remote API, or automatic cloud upload in this project.
- Android backup is disabled in the manifest. Export important trips before uninstalling the app or clearing its data.
- Deleting a trip or individual recorded annotation is destructive to the local database. Previously shared copies of a CSV are outside the app's control.

---

## Data integrity and field-use checklist

Before a real collection campaign:

- [ ] Run `flutter analyze` and `flutter test` on the development machine.
- [ ] Install and open the app on the target Android phone.
- [ ] Create a test trip and add several annotations rapidly.
- [ ] Edit one recorded annotation and verify that its original timestamps remain unchanged.
- [ ] Delete one test record and confirm it is absent from the next CSV export.
- [ ] End the trip and verify that the CSV is created and can be shared.
- [ ] Verify row order is chronological by `t_mono_ns`.
- [ ] Verify local date/time includes the intended timezone offset and millisecond component.
- [ ] Compare annotation `t_mono_ns` with the sensor logger's monotonic timestamps on the same device.
- [ ] Verify optional GPS metadata and accuracy are reasonable for the test location.
- [ ] Export and keep a backup of every completed trip before deleting or reinstalling the app.

Do not treat this checklist as complete until the target phone and the specific sensor-logging app have been tested together.

---

## Current version

`1.2.1+7` — includes trip management, custom annotation-button management and ordering, per-record correction/deletion, persistent light/dark themes, UTC and monotonic timestamp export, optional GPS metadata, and a static-analysis dead-code cleanup.

The SQLite schema version is `6` in this release. Existing app data should be preserved when updating over an installed copy; avoid uninstalling the app before exporting important sessions.

## License

No license file is included in this source bundle. Add a `LICENSE` file before publishing the repository for reuse, and specify the license that the project owners choose.
