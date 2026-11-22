# Project Description — Road Guard Annotator

## GitHub repository description

Offline Flutter Android app for Road Guard field annotations. Records customizable, timestamped road-event labels with Android monotonic and UTC clocks, optional GPS metadata, trip management, and chronological CSV export for IMU synchronization.

## One-line summary

A lightweight Android annotation tool that records human-observed road events with precise monotonic timestamps so manual labels can be aligned with smartphone IMU recordings.

## Extended description

Road Guard Annotator is a field-data collection companion for the Road Guard road-anomaly detection project. It allows a researcher or passenger annotator to create a named trip, define reusable annotation buttons (for example BUMP, POTHOLE, OTHER, or custom labels), and capture each observation with an Android monotonic timestamp and a UTC wall-clock timestamp. Records are saved locally in SQLite, can be reviewed and corrected, and can be exported as a chronological UTF-8 CSV file for later ground-truth engineering and synchronization with accelerometer/gyroscope recordings.

The app is designed for offline annotation and transparent timestamp handling. It does not capture IMU streams, run an AI classifier, or automatically verify the physical event; those tasks belong to the separate sensor-recording and model-development pipeline.

## Suggested GitHub topics

`flutter` · `dart` · `android` · `kotlin` · `sqlite` · `csv-export` · `data-collection` · `data-annotation` · `sensor-data` · `imu` · `road-anomaly-detection` · `ground-truth`

## Short app-store style description

Record road-event annotations during field trips. Create custom buttons, timestamp each tap with Android monotonic and UTC clocks, optionally attach GPS metadata, and export a chronological CSV for IMU data analysis.

## Important scope statement

Current version `1.2.1` records one annotation row per button tap (`MANUAL_BUTTON_TAP`). It is not an accelerometer/gyroscope logger, not an automatic pothole detector, and not yet a guided three-marker event-boundary tool.
