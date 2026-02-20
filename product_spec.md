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
* **`WorkoutSession`:** `id`, `date`, `file_name`, `type` (Workout vs GPX), `duration_seconds`, `distance_km`, `avg_hr`, `avg_pace`, `avg_speed`, `elevation_gain`, `is_uploaded_to_strava`.
* **`LibraryItem`:** `id`, `name`, `type` (JSON/GPX), `file_path` (local), `completion_count`, `best_time_seconds` (PR - GPX only).

## 4. Core Features & App Flow

### Feature 1: The Library & Cloud Sync
* **Public Cloud Library:** The app fetches available files from a public GitHub repository.
  * Workouts: `GET https://api.github.com/repos/ganeshapp/sub3/contents/contents/workouts` (Parses JSON).
  * Routes: `GET https://api.github.com/repos/ganeshapp/sub3/contents/contents/virtualrun` (Parses GPX).
* **UI:** A dual-tab library ("Structured Workouts" & "Virtual Runs"). Users can download these files to local storage.
* **Stats Tracking:** Each item in the library UI displays `completion_count`. Virtual runs also display a `best_time_seconds` (PR) badge if completed previously.

### Feature 2: Device Pairing & Connection Management
* **Setup Screen:** Scans and connects to 1 Treadmill (FTMS `0x1826`) and 1 Vitals Sensor (Heart Rate `0x180D` via Chest Strap or Garmin Watch). Cadence should be extracted if provided by the watch/strap.
* **Auto-Recovery Engine (Crucial):** * Listen to `device.connectionState`. 
  * If a connection drops mid-workout, DO NOT crash or stop the timer. Log `null` or hold the last known value, show a reconnecting UI indicator, and loop a background connection retry.

### Feature 3: Live Workout Dashboard
* **UI Layout:** Sleek, large typography. 
* **Metrics Displayed:** Heart Rate, Current Pace, Average Pace, Current Speed, Average Speed, Incline, Distance, Time, and Cadence.
* **Visualizer:** * *For GPX:* A 2D elevation profile of the route. A red progress dot moves horizontally based on distance covered.
  * *For JSON:* A bar chart of the intervals. A red progress dot moves horizontally based on time elapsed.
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

### Feature 5: Post-Workout Summary & Strava Sync
* **Summary Screen:** Displays total metrics. Features two buttons: "Save & Exit" and "Discard".
* **Strava Integration:** (Requires OAuth setup in User Settings).
  * Feature an "Upload to Strava" button.
  * *Data Compilation:* Convert the 1-second telemetry arrays into a standard `.TCX` file format.
  * *Critical API Flag:* The POST request to Strava's `/uploads` endpoint MUST include the flag `trainer=1` or `sport_type="VirtualRun"`. (This prevents the user from being flagged on real-world leaderboards).

### Feature 6: Stats & History Page
* **UI:** A calendar or chart view displaying historical runs.
* **Metrics:** Weekly and Monthly mileage/volume totals.
* **Export:** A button on individual historical runs to manually export the `.TCX` file to the phone's local storage.

### Feature 7: Settings & About Page
* **Settings:** Toggle Strava linking (OAuth), User Profile (Height/Weight if needed for future metrics).
* **About Page:** * Explains app features.
  * Link to Workout Planner: `https://www.gapp.in/sub3/`
  * Developer Credits: `www.gapp.in`