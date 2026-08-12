# Product Requirements Document (PRD): Sub3 - Indoor Running Zapp

## 1. Product Overview
"Sub3" is a lightweight, high-performance Flutter mobile application designed exclusively for indoor treadmill runners. It acts as a bridge between structured workouts (JSON) or real-world virtual routes (GPX) and BLE-enabled fitness equipment. 
Target Platforms: Android (Primary), iOS (Future compatibility).

## 2. Technical Stack & Architecture
* **Framework:** Flutter (Dart). Focus on sleek, highly responsive UI (Dark mode preferred).
* **State Management:** Riverpod (crucial for managing concurrent live BLE streams).
* **Bluetooth:** `flutter_blue_plus` for FTMS Treadmill and Heart Rate/Cadence sensors.
* **Local Database:** SQLite or Isar for storing workout history, library files, and PRs.
* **Background/Screen:** `wakelock_plus` (App must prevent screen sleep during active workouts to maintain BLE streams).

## 3. Data Models (Local Database)
SQLite file `sub3.db`, currently at schema version 3. Upgrades only ever `ALTER TABLE ... ADD COLUMN`, so history and library stats survive an app update.
* **`WorkoutSession`:** `id`, `date`, `file_name`, `display_name`, `type` (Workout vs GPX), `duration_seconds`, `distance_km`, `avg_hr`, `avg_pace`, `avg_speed`, `elevation_gain`.
  * `display_name` (added in v3) is the human-readable route/workout name, saved with every new session. Rows from older versions have it null; those are back-filled at read time from `library_items` (cached metadata name), and failing that from a prettified file name (extension stripped, `_` → space).
  * `is_uploaded_to_strava` still exists in the table as a leftover of the removed Strava feature. Nothing reads or writes it.
* **`LibraryItem`:** `id`, `name`, `type` (JSON/GPX), `file_path` (local), `completion_count`, `best_time_seconds` (PR - GPX only), `sha`, `metadata_json`, `preview_points`, `pr_trace`.
  * `pr_trace` (added in v3) holds the best-run distance trace used to race a ghost on routes. Format: `{"v":1,"step":<seconds between samples>,"total":<PR seconds>,"m":[<cumulative metres>, ...]}` — one sample per second, thinned by keeping every `step`-th second so a trace never exceeds 1800 points. The last sample is always the true finish, and `total` times the final segment. A bare JSON array is also accepted and read as one sample per second. Written only when a run sets a new best time; a library re-sync carries it across.

## 4. Core Features & App Flow

### App Shell & Navigation
* Three tabs: **Library** (home, and the default tab), **Stats**, **Settings**. There is no Dashboard tab — it could not do anything pairing did not already do from Settings.
* The Library screen carries a compact one-row status strip at the top: a treadmill chip and a heart-rate chip showing the live BPM. Either chip opens Pair Devices.

### Feature 1: The Library & Cloud Sync
* **Public Cloud Library:** The app fetches available files from a public GitHub repository.
  * Workouts: `GET https://api.github.com/repos/ganeshapp/sub3/contents/contents/workouts` (Parses JSON).
  * Routes: `GET https://api.github.com/repos/ganeshapp/sub3/contents/contents/virtualrun` (Parses GPX).
* **UI:** A dual-tab library ("Structured Workouts" & "Virtual Runs"). Users can download these files to local storage.
* **Stats Tracking:** Each item in the library UI displays `completion_count`. Virtual runs also display a `best_time_seconds` (PR) badge if completed previously.
* **What counts as a completion:** a virtual run counts once covered distance reaches 99% of the route distance; a structured workout counts once elapsed time reaches 99% of the planned duration. Only a completed virtual run can set a new best time. A run that stops early still saves to history — it just earns no badge.
* **PR trace:** a finished virtual run that beats the stored best time also replaces the route's `pr_trace`, so the ghost always belongs to the current PR. Discarding the run restores the previous count, best time and trace together.

### Feature 2: Device Pairing & Connection Management
* **Setup Screen:** Scans and connects to 1 Treadmill (FTMS `0x1826`) and 1 Vitals Sensor (Heart Rate `0x180D` via Chest Strap or Garmin Watch). Cadence should be extracted if provided by the watch/strap.
* **HR keep-alive (Crucial for watches):** the app subscribes to the HR Measurement characteristic (`0x2A37`) the moment the sensor connects, and holds that subscription for the whole app session. It survives navigation and the start and end of a workout; only an explicit disconnect tears it down. Watches such as the Garmin Forerunner drop the link when nobody is subscribed, so this is what keeps them paired.
* **Live BPM:** the latest reading is published as a stream. Pair Devices shows a red heart and `146 bpm` next to a connected sensor, and so does the Library status chip; both read `--` until the first packet arrives.
* **A frozen reading is not a reading:** keeping the subscription alive means nothing clears the last BPM at the end of a run, so a watch that dies mid-run would otherwise have its last value recorded into every telemetry point, into `avg_hr` and into the TCX for the rest of the run — and the run after. Every HR packet (re)arms a 10-second staleness timer; when it fires the reading drops to 0 and that zero is published, so the run records no HR and the chips go back to `--`. Cadence is untouched, since RSC arrives on its own characteristic. When auto-reconnect runs out of attempts the subscription is torn down too, so `isHrListening` stops lying and the next run's top-up re-subscribes.
* **After a reconnect the treadmill is re-commanded:** `BleService.onReconnected` fires once notifications and `requestControl()` are back, and the workout engine clears `_lastSentSpeed` / `_lastSentIncline` / `_lastSentGpxIncline` and re-sends the current segment as a transition. Without it a machine that reset its target on disconnect would sit there for the rest of the block, because the rounded target still matched the last one sent.
* **Auto-Recovery Engine (Crucial):** * Listen to `device.connectionState`. 
  * If a connection drops mid-workout, DO NOT crash or stop the timer. Log `null` or hold the last known value, show a reconnecting UI indicator, and loop a background connection retry.
  * A paired HR sensor reconnects whatever the app is doing — a watch that drops out between runs has to be back before the next one starts. The treadmill only reconnects while a workout is running.
  * Disconnecting invalidates the characteristic handles, so notifications are re-enabled (and treadmill control re-requested) after every successful reconnect, before the device is reported as back.

### Feature 3: Live Workout Dashboard
* **UI Layout:** Sleek, large typography. 
* **Metrics Displayed:** Heart Rate, Current Pace, Average Pace, Current Speed, Average Speed, Incline, Distance, Time, and Cadence.
* **Metric help:** every metric tile with a glossary entry carries a small `(?)`; tapping the tile opens a plain-language explanation. One shared glossary (`lib/widgets/metric_info.dart`, `showMetricInfo(context, key)`) serves the live tiles and the summary tiles.
* **Visualizer:** * *For GPX:* A 2D elevation profile of the route. A red progress dot moves horizontally based on distance covered.
  * *For JSON:* A bar chart of the intervals. A red progress dot moves horizontally based on time elapsed.
* **Ghost racing (routes only):** when the route has a `pr_trace`, a second dimmer white dot with a soft glow shows where the best-ever run was at this moment, and a chip under the distance bar reads `0:12 ahead of PR` (green) or `0:05 behind PR` (amber). The delta is a time difference at equal distance — when the ghost passed the distance you are at now — which is the comparison runners actually understand. The ghost freezes at the finish line once its trace runs out, and the chip reads `PR finished` once you are further along than the ghost ever got. No trace means no dot and no chip; a short or corrupt trace is ignored rather than allowed to break a run.
* **Session Controls:** * **PAUSE:** Sends FTMS Stop/Pause (`0x08`). Suspends appending data to the 1-second telemetry arrays (prevents stationary time from ruining average pace/HR). Changes button to "RESUME".
  * **RESUME:** Sends FTMS Start (`0x07`). Resumes data logging and re-sends current segment targets.
  * **STOP:** Ends the workout and transitions to the Post-Workout Summary.

### Feature 4: The Execution Engine (Hardware Control)
**Rule: The Source of Truth is the Treadmill's Broadcasted Data (Read), NOT the App's Commanded Data (Write).**

* **GPX Virtual Run Logic:**
  * App calculates distance traveled and reads upcoming elevation.
  * *Smoothing:* Apply a moving average filter to the GPX elevation data to prevent "jumpy" incline commands.
  * *Look-Ahead:* Send the FTMS Incline command 3-5 seconds *before* the visual dot hits the hill to account for physical motor lag.
  * *Speed:* Strictly manual. The user controls treadmill speed manually; the app only controls incline.
* **JSON Structured Workout Logic:**
  * *Safety Start:* Enforce a mandatory 3-second countdown before sending the first speed command.
  * *Automated Control:* App sends Speed (`0x02`) and Incline (`0x03`) commands at the start of each interval block. (Note: Send Incline percentage exactly as read from JSON, e.g., 5% = command `0x05`).
  * *Manual Override Detection:* If the FTMS Read characteristic reports a speed different from the currently commanded interval speed, the app assumes a manual override. The app must immediately pause sending automated speed commands until the next interval block begins, logging the physical speed actually run.

### Feature 5: Post-Workout Summary & Export
* **Summary Screen:** Titled with the route/workout display name. Displays total metrics, each explained in plain words on tap (`(?)` cue). Four actions: "Save TCX to Downloads", "Share", "Save & Exit" and "Discard".
* **Data Compilation:** The 1-second telemetry arrays are converted into a standard `.TCX` file, kept with the session so it can be exported again later from history. The Creator name keeps the "with barometer" suffix so importers trust the app's elevation data.
* **Discard:** Exporting saves the session first, so Discard deletes that row and its TCX file again and reverts the completion badge / best time.

### Feature 6: Stats & History Page
* **UI:** A chronological list of historical runs, each showing the route/workout display name.
* **Metrics:** Weekly, Monthly, Yearly and Lifetime mileage/volume totals.
* **Export:** Every history row offers "Save to Downloads" and "Share" (3-dot menu or long-press sheet), file named `Sub3_<display name>_<yyyy-MM-dd>.tcx`.

### Feature 6b: TCX Export Destinations
* **Android:** a Kotlin MethodChannel (`com.gapp.sub3/exports`, method `saveToDownloads(fileName, mimeType, content)`) writes into the phone's public Downloads folder — `MediaStore.Downloads` with `IS_PENDING` on API 29+, `Environment.getExternalStoragePublicDirectory` plus a `MediaScannerConnection` scan below that (`WRITE_EXTERNAL_STORAGE` is declared with `maxSdkVersion="28"`). Returns the user-facing path (`Download/<name>.tcx`), which the confirmation snackbar shows.
* **iOS:** no shared Downloads folder, so both actions open the share sheet and the confirmation says so.
* **Share:** `share_plus` share sheet, from a temp copy named after the run.
* Nothing is uploaded anywhere; runs are imported into training sites by hand.

### Feature 7: Settings & About Page
* **Settings:** Device pairing, User Profile (Height/Weight if needed for future metrics).
* **About Page:** * Explains app features.
  * Link to Workout Planner: `https://www.gapp.in/sub3/`
  * Developer Credits: `www.gapp.in`