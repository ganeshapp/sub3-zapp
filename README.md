# Sub3 - Indoor Running Zapp

A lightweight, high-performance Flutter application designed exclusively for indoor treadmill runners. Sub3 bridges the gap between structured workouts or virtual routes and BLE-enabled fitness equipment.

## Download

Get the latest APK from the [Releases page](https://github.com/ganeshapp/sub3-zapp/releases).

Pick the APK that matches your device architecture:
- **arm64** -- Most modern Android phones (recommended)
- **arm32** -- Older 32-bit Android devices
- **x86_64** -- Emulators and x86 devices

## Features

### Workout Library
- Browse and download structured JSON workouts and GPX virtual routes from a public GitHub repository.
- Rich card UI with mini visualizers: color-coded interval bar charts for JSON, top-down 2D route maps for GPX.
- Metadata display: name, duration, distance, pace, elevation gain, description.
- SHA-based caching with versioning. Only changed files are re-fetched from GitHub, so the Library tab opens instantly.

### BLE Device Pairing
- Connect to FTMS treadmills via Bluetooth Low Energy.
- Connect to heart rate monitors (HR Service 0x180D).
- Connect to Running Speed and Cadence sensors like Garmin watches (RSC Service 0x1814).
- Auto-reconnect during active workouts.

### Live Workout Dashboard
- Real-time metrics: HR, pace, speed, incline, cadence, distance, and averages.
- 2D visualizer: interval bar chart for JSON workouts, top-down route map with glowing red progress line for GPX.
- Distance progress bar for GPX routes showing current distance, distance remaining, and total distance.
- Manual Control toggle: switch between automatic treadmill control and manual override at any time.
- Redesigned stop UX: large inline "CONFIRM STOP" button instead of a dialog. Tap anywhere else to dismiss.

### Treadmill Control
- Sends FTMS speed and incline commands automatically for JSON workouts.
- GPX routes: incline-only control with 30m look-ahead and elevation smoothing (moving average filter). Downhill is clamped to 0%.
- FTMS incline encoding uses proper 0.1% resolution (1% = payload 10, 5% = payload 50).
- Physical stop detection: if the treadmill belt stops for 5 consecutive seconds mid-workout, the app auto-finishes.

### Elevation
- GPX files without elevation tags are automatically augmented with real-world elevation data from the Open-Elevation API (free DEM lookup).
- GPX altitude is interpolated from the route's elevation data during the workout.
- JSON workout altitude is computed from incline percentage and horizontal distance.
- TCX files include AltitudeMeters in every trackpoint. Creator name includes "with barometer" so Strava trusts the app's elevation data.

### Strava Integration
- Upload completed runs as TCX files with sport_type=VirtualRun.
- OAuth Authorization Code flow with secure token storage (flutter_secure_storage).
- Virtual GPS positions (lat/lon) interpolated into TCX for proper Strava route maps.
- Elevation gain, heart rate, cadence, and speed data all included in TCX.
- Connect and disconnect Strava from the Settings page.

### Auto-Screenshots
- The app captures a screenshot of the live dashboard every 10 minutes during a workout.
- Screenshots are saved to the phone's gallery in a "Sub3" album.
- You can manually add them to your Strava activity using "Add Media".

### Stats and History
- Volume summaries: This Week, This Month, This Year, and Lifetime.
- Full chronological run history with distance, pace, and Strava upload status.
- Export any session as a TCX file. Delete any session from history.

### Other
- Wakelock: screen stays on during active workouts. Disabled on pause, stop, or discard.
- User profile: height and weight stored locally via SharedPreferences.
- About page with links to the workout planner and developer site.

## Permissions

The app requests the following Android permissions:
- **Bluetooth** -- Scanning, connecting, and communicating with FTMS treadmills and sensors.
- **Location** -- Required by Android for BLE scanning (no location data is collected or stored).
- **Internet** -- Fetching workouts from GitHub, elevation data from Open-Elevation, and uploading to Strava.
- **Files and Media** -- Saving workout screenshots to the phone's gallery.
- **Wake Lock** -- Keeping the screen on during active workouts.

## Setup (Strava)

To enable Strava uploads, you need your own Strava API application credentials.

1. Create an API Application at https://www.strava.com/settings/api
2. Set the Authorization Callback Domain to `sub3.app`
3. Create a `.env` file in the project root:

```
STRAVA_CLIENT_ID=your_client_id_here
STRAVA_CLIENT_SECRET=your_client_secret_here
```

The `.env` file is gitignored and will not be committed to the repository. See `.env.example` for the template.

## Tech Stack

- **Framework:** Flutter (Dart)
- **State Management:** Riverpod (AsyncNotifier, StateProvider)
- **Bluetooth:** flutter_blue_plus (FTMS, Heart Rate, RSC services)
- **Database:** SQLite via sqflite (library items, workout sessions)
- **Auth:** flutter_web_auth_2 (OAuth redirect), flutter_secure_storage (encrypted token storage)
- **Elevation:** Open-Elevation API (DEM lookup for GPX files without elevation data)
- **Gallery:** gal (saving screenshots to phone gallery)
- **Protocols:** FTMS opcodes for speed (0x02), incline (0x03), start/stop/pause (0x07/0x08)

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
