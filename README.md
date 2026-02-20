# Sub3 - Indoor Running Zapp

A lightweight, high-performance Flutter application designed exclusively for indoor treadmill runners. Sub3 bridges the gap between structured workouts or virtual routes and BLE-enabled fitness equipment.

## Download

Get the latest APK from the [Releases page](https://github.com/ganeshapp/sub3-zapp/releases).

Pick the APK that matches your device architecture:
- **Sub3-v1.0.0-arm64.apk** -- Most modern Android phones (recommended)
- **Sub3-v1.0.0-arm32.apk** -- Older 32-bit Android devices
- **Sub3-v1.0.0-x86_64.apk** -- Emulators and x86 devices

## Features

- **Cloud Workout Library** -- Browse and download structured JSON workouts and GPX virtual routes from a public GitHub repository.
- **BLE Device Pairing** -- Connect to FTMS treadmills and heart rate monitors (chest straps, Garmin watches) via Bluetooth Low Energy.
- **Live Workout Dashboard** -- Real-time metrics (HR, pace, speed, incline, cadence, distance) with a 2D visualizer for intervals and elevation profiles.
- **Automated Treadmill Control** -- The app sends FTMS speed and incline commands for JSON workouts, and incline-only commands with look-ahead for GPX routes.
- **Manual Override Detection** -- If you change the treadmill speed manually mid-interval, the app detects it and stops overriding until the next block.
- **Strava Integration** -- Upload completed runs to Strava as TCX files with `trainer=1` and `sport_type=VirtualRun` to stay off real-world leaderboards.
- **Stats and History** -- Weekly and monthly running volume summaries with a full run history. Export any past session as a TCX file.
- **Wakelock** -- Screen stays on during active workouts to maintain BLE connections. Automatically disabled on pause, stop, or discard.

## Permissions

The app requests the following Android permissions at runtime:
- **Bluetooth** -- Scanning, connecting, and communicating with FTMS treadmills and HR sensors.
- **Location** -- Required by Android for BLE scanning (no location data is collected or stored).
- **Internet** -- Fetching workouts from GitHub, downloading Google Fonts, and uploading to Strava.

## Tech Stack

- **Framework:** Flutter (Dart)
- **State Management:** Riverpod
- **Bluetooth:** flutter_blue_plus (FTMS and Heart Rate services)
- **Database:** SQLite via sqflite
- **Protocols:** FTMS opcodes for speed (0x02), incline (0x03), start/stop/pause

## Building from Source

```
flutter pub get
flutter build apk --split-per-abi --release
```

The split APKs will be in `build/app/outputs/flutter-apk/`.

## Links

- Workout Planner: https://www.gapp.in/sub3/
- Developer: https://www.gapp.in
