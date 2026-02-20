# Developer Reference: Sub3 TCX XML Export & Strava API Integration

## 1. Context
When a user finishes a workout and clicks "Upload to Strava", the app must compile the 1-second telemetry arrays into a standard `.TCX` (Training Center XML) file and push it via a `multipart/form-data` POST request to the Strava API.

## 2. Strava API Upload Parameters
**Endpoint:** `POST https://www.strava.com/api/v3/uploads`

The request body must include the following parameters to ensure the treadmill run does not trigger real-world Strava segments:
* `file`: The `.tcx` file itself.
* `data_type`: `"tcx"`
* `trainer`: `1` (Crucial: This flags the activity as stationary/treadmill).
* `sport_type`: `"VirtualRun"` (Ensures it goes to virtual leaderboards, not real-world CRs).
* `name`: Optional (e.g., "Sub3 Tempo Run").
* `description`: Optional.

## 3. The TCX XML Schema (Strict Format)
Cursor must generate the XML exactly as shown below. 

### Critical Formatting Rules:
* **Time:** Must be in strict ISO 8601 UTC format (e.g., `2024-01-01T12:00:00.000Z`).
* **Creator Tag:** The `<Name>` tag MUST include the phrase "with barometer" (e.g., `Sub3 App with barometer`). This forces Strava to trust the calculated elevation data instead of overwriting it.
* **Cadence & Speed:** Because base TCX does not support running cadence, these metrics MUST be nested inside the `<Extensions><TPX>` block using the `ActivityExtension/v2` namespace. Speed must be in meters per second (m/s).

### Example TCX Structure:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  xsi:schemaLocation="[http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2](http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2) [http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd](http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd) [http://www.garmin.com/xmlschemas/ActivityExtension/v2](http://www.garmin.com/xmlschemas/ActivityExtension/v2) [http://www.garmin.com/xmlschemas/ActivityExtensionv2.xsd](http://www.garmin.com/xmlschemas/ActivityExtensionv2.xsd)"
  xmlns:ns5="[http://www.garmin.com/xmlschemas/ActivityExtension/v2](http://www.garmin.com/xmlschemas/ActivityExtension/v2)"
  xmlns:xsi="[http://www.w3.org/2001/XMLSchema-instance](http://www.w3.org/2001/XMLSchema-instance)"
  xmlns="[http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2](http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2)">
  <Activities>
    <Activity Sport="Running">
      <Id>2024-01-01T12:00:00.000Z</Id>
      
      <Creator xsi:type="Device_t">
        <Name>Sub3 App with barometer</Name>
      </Creator>
      
      <Lap StartTime="2024-01-01T12:00:00.000Z">
        <TotalTimeSeconds>1800.0</TotalTimeSeconds>
        <DistanceMeters>5000.0</DistanceMeters>
        <Intensity>Active</Intensity>
        <TriggerMethod>Manual</TriggerMethod>
        <Track>
          
          <Trackpoint>
            <Time>2024-01-01T12:00:01.000Z</Time>
            
            <Position>
              <LatitudeDegrees>37.5665</LatitudeDegrees>
              <LongitudeDegrees>126.9780</LongitudeDegrees>
            </Position>
            
            <AltitudeMeters>15.2</AltitudeMeters>
            <DistanceMeters>2.7</DistanceMeters>
            
            <HeartRateBpm>
              <Value>145</Value>
            </HeartRateBpm>
            
            <Extensions>
              <TPX xmlns="[http://www.garmin.com/xmlschemas/ActivityExtension/v2](http://www.garmin.com/xmlschemas/ActivityExtension/v2)">
                <Speed>3.33</Speed>
                <RunCadence>170</RunCadence>
              </TPX>
            </Extensions>
          </Trackpoint>
          </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>