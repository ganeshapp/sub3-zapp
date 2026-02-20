# Sub3 - Indoor Running Zapp

A lightweight, high-performance Flutter application designed exclusively for indoor treadmill runners. Sub3 bridges the gap between structured workouts or virtual routes and BLE-enabled fitness equipment.

## Download

Get the latest APK from the [Releases page](https://github.com/ganeshapp/sub3-zapp/releases).

Pick the APK that matches your device architecture:
- **arm64** -- Most modern Android phones (recommended)
- **arm32** -- Older 32-bit Android devices
- **x86_64** -- Emulators and x86 devices

## Features

- **Cloud Workout Library** -- Browse and download structured JSON workouts and GPX virtual routes from a public GitHub repository.
- **BLE Device Pairing** -- Connect to FTMS treadmills and heart rate monitors (chest straps, Garmin watches) via Bluetooth Low Energy.
- **Live Workout Dashboard** -- Real-time metrics (HR, pace, speed, incline, cadence, distance) with a 2D visualizer for intervals and elevation profiles.
- **Automated Treadmill Control** -- The app sends FTMS speed and incline commands for JSON workouts, and incline-only commands with look-ahead for GPX routes.
- **Manual Override Detection** -- If you change the treadmill speed manually mid-interval, the app detects it and stops overriding until the next block.
- **Strava Integration** -- Upload completed runs to Strava as TCX files with `trainer=1` and `sport_type=VirtualRun` to stay off real-world leaderboards. Uses proper OAuth Authorization Code flow with secure token storage.
- **Stats and History** -- Weekly and monthly running volume summaries with a full run history. Export any past session as a TCX file.
- **Wakelock** -- Screen stays on during active workouts to maintain BLE connections. Automatically disabled on pause, stop, or discard.

## Permissions

The app requests the following Android permissions at runtime:
- **Bluetooth** -- Scanning, connecting, and communicating with FTMS treadmills and HR sensors.
- **Location** -- Required by Android for BLE scanning (no location data is collected or stored).
- **Internet** -- Fetching workouts from GitHub, downloading Google Fonts, and uploading to Strava.

## Setup (Strava)

To enable Strava uploads, you need your own Strava API application credentials.

1. Create an API Application at https://www.strava.com/settings/api
2. Set the Authorization Callback Domain to `sub3.app`
3. Create a `.env` file in the project root:

```
STRAVA_CLIENT_ID=your_client_id_here
STRAVA_CLIENT_SECRET=your_client_secret_here
```

The `.env` file is gitignored and will not be committed to the repository.

## Tech Stack

- **Framework:** Flutter (Dart)
- **State Management:** Riverpod
- **Bluetooth:** flutter_blue_plus (FTMS and Heart Rate services)
- **Database:** SQLite via sqflite
- **Auth:** flutter_web_auth_2 (OAuth redirect), flutter_secure_storage (token persistence)
- **Protocols:** FTMS opcodes for speed (0x02), incline (0x03), start/stop/pause

## Building from Source

```
flutter pub get
flutter build apk --split-per-abi --release
```

The split APKs will be in `build/app/outputs/flutter-apk/`.

Requires Android 7.0 (API 24) or higher.

## Links

- Workout Planner: https://www.gapp.in/sub3/
- Developer: https://www.gapp.in
