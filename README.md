# Sub3 - Indoor Running Zapp

A lightweight, high-performance Flutter application designed exclusively for indoor treadmill runners. Sub3 bridges the gap between structured workouts or virtual routes and BLE-enabled fitness equipment.

## Download

Get the latest APK from the [Releases page](https://github.com/ganeshapp/sub3-zapp/releases).

Pick the APK that matches your device architecture:
- **arm64** -- Most modern Android phones (recommended)
- **arm32** -- Older 32-bit Android devices
- **x86_64** -- Emulators and x86 devices

## Features

### Workout Library (the home screen)
- Three tabs: Library, Stats, Settings. The Library opens first — it is where every run starts.
- A compact status strip at the top of the Library shows your treadmill and your heart rate sensor, with a live BPM. Tap either chip to pair.
- Your treadmill has to be paired before a run can start — without it there is no speed to record and nothing to control. Until it is, the strip turns into `Connect your treadmill to start a run` with a **Pair** button, and the play buttons are greyed out. Tap one anyway and it tells you why, with a Pair shortcut. A heart rate sensor is optional and never blocks a run.
- Browse and download structured JSON workouts and GPX virtual routes from a public GitHub repository.
- Rich card UI with mini visualizers: color-coded interval bar charts for JSON, top-down 2D route maps for GPX.
- Metadata display: name, duration, distance, pace, elevation gain, description.
- SHA-based caching with versioning. Only changed files are re-fetched from GitHub, so the Library tab opens instantly.

### BLE Device Pairing
- Connect to FTMS treadmills via Bluetooth Low Energy. The treadmill is required to start a structured workout or a virtual run; the heart rate sensor is always optional.
- Connect to heart rate monitors (HR Service 0x180D).
- Connect to Running Speed and Cadence sensors like Garmin watches (RSC Service 0x1814).
- Live heart rate on the pairing screen and on the Library status chip, so you can see the strap or watch working before you start.
- The heart rate link is opened the moment the sensor connects and stays open for the whole session — moving between tabs or starting and stopping a run never drops it. Watches that idle out when nobody is listening stay paired.
- Auto-reconnect: a paired heart rate sensor is always brought back, the treadmill during active workouts. Notifications are re-enabled after every reconnect. A run already under way is never stopped because a device dropped — the pairing requirement is only about starting.

### Live Workout Dashboard
- Real-time metrics: HR, pace, speed, incline, cadence, distance, and averages.
- 2D visualizer: interval bar chart for JSON workouts, top-down route map with glowing red progress line for GPX.
- Distance progress bar for GPX routes showing current distance, distance remaining, and total distance.
- Manual Control toggle: switch between automatic treadmill control and manual override at any time.
- Redesigned stop UX: large inline "CONFIRM STOP" button instead of a dialog. Tap anywhere else to dismiss.
- Tap any metric marked with a small (?) — on the live screen or the summary — for a plain-English explanation of what the number means.

### Race Your Ghost
- Finish a virtual route faster than before and Sub3 keeps the distance trace of that run.
- Next time you run the route, a dimmer white dot shows where your best-ever run was at that exact moment, alongside your red dot.
- A chip under the distance bar reads `0:12 ahead of PR` in green or `0:05 behind PR` in amber — the time difference at the distance you have covered.
- The ghost stops at the finish line when it is done; the chip then says the PR is finished. Routes with no personal best simply have no ghost.

### Treadmill Control
- Sends FTMS speed and incline commands automatically for JSON workouts.
- GPX routes: incline-only control with 30m look-ahead and elevation smoothing (moving average filter). Downhill is clamped to 0%.
- FTMS incline encoding uses proper 0.1% resolution (1% = payload 10, 5% = payload 50).
- Physical stop detection: if the treadmill belt stops for 5 consecutive seconds mid-workout, the app auto-finishes.

### Elevation
- GPX files without elevation tags are automatically augmented with real-world elevation data from the Open-Elevation API (free DEM lookup).
- GPX altitude is interpolated from the route's elevation data during the workout.
- JSON workout altitude is computed from incline percentage and horizontal distance.
- Exported files include altitude in every trackpoint. The TCX Creator name includes "with barometer" so the site you import into trusts the app's elevation data.

### Export Your Runs
- Every saved run keeps two export files with virtual GPS positions, elevation, heart rate, cadence, and speed:
  - **FIT (recommended):** tagged `sport: running` + `sub_sport: virtual_activity`, so a hand-uploaded file lands on Strava as a **Virtual Run** with no manual editing.
  - **TCX (proven fallback):** exactly the file the app has always produced; imports as a plain Run.
- **Save FIT / TCX to Downloads** writes the file straight into the phone's Downloads folder, where any file manager can see it. The file is named `Sub3_<run name>_<date>.fit` / `.tcx`.
- **Share FIT / TCX** hands the same file to the system share sheet (email, cloud drive, messaging app).
- All actions are on the post-workout summary and on any row in Run History (3-dot menu or long-press). History entries appear only for the files a session actually has — runs saved before the FIT feature have just the TCX.
- On iOS, where there is no shared Downloads folder, the actions use the share sheet.
- Upload the FIT (or TCX) to your training site by hand — nothing is sent anywhere automatically.

### Auto-Screenshots
- The app captures a screenshot of the live dashboard every 10 minutes during a workout.
- Screenshots are saved to the phone's gallery in a "Sub3" album.
- Add them to your online activity yourself if you want them there.

### Stats and History
- Volume summaries: This Week, This Month, This Year, and Lifetime.
- Full chronological run history showing the route or workout name, distance, and pace.
- Save or share any session's FIT or TCX file. Delete any session from history.
- Completion badges: a run counts as completed once you cover 99% of a route or run 99% of a structured workout's planned time. Routes also keep your best time, and the ghost trace that goes with it.

### Other
- Wakelock: screen stays on during active workouts. Disabled on pause, stop, or discard.
- User profile: height and weight stored locally via SharedPreferences.
- About page with links to the workout planner and developer site.

## Permissions

The app requests the following Android permissions:
- **Bluetooth** -- Scanning, connecting, and communicating with FTMS treadmills and sensors.
- **Location** -- Required by Android for BLE scanning (no location data is collected or stored).
- **Internet** -- Fetching workouts from GitHub and elevation data from Open-Elevation.
- **Files and Media** -- Saving workout screenshots to the phone's gallery. On Android 9 and older, also writing FIT/TCX files into the Downloads folder (Android 10+ needs no permission for that).
- **Wake Lock** -- Keeping the screen on during active workouts.

## Tech Stack

- **Framework:** Flutter (Dart)
- **State Management:** Riverpod (AsyncNotifier, StateProvider)
- **Bluetooth:** flutter_blue_plus (FTMS, Heart Rate, RSC services)
- **Database:** SQLite via sqflite (library items, workout sessions)
- **Export:** fit_tool for the FIT encoder, MediaStore via a Kotlin MethodChannel (`com.gapp.sub3/exports`) for the Downloads folder, share_plus for the share sheet
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
