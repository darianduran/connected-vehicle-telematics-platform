# 3.0 Detailed Component Design

## 3.1 Telemetry Ingestion Pipeline

### 3.1.1 Edge Device

Embedded in vehicle and interfaces its CAN Bus. Decodes OBD-II messages and publishes to IoT Core via MQTT. MQTT messages published to IoT Core using basic ingest (`$aws/rules/{rule-name}` topic prefix).

The Edge Device must mutually authenticate (mTLS) with IoT Core before it accepts messages. While CAN bus is active, the Edge Device buffers all records generated and publishes every second. During long periods of inactivity (parked/deep sleep), the Edge Device disconnects for occasional gaps. During connectivity loss, the Edge Device buffers data and transmits upon reconnection. For signals that generate more than once in a single second, the Edge Device retains the peak value only.

**CAN Signal Catalog:**
The DBC signal catalog is the authoritative source for all CAN message and signals. The DBC file is what allows the device to decode the data into human-readable format. Raw-CAN frames are decoded before they are published to IoT Core.

Below is an example of the key signals the platform collects:

| Message Group Prefix | Module | Example Signals |
|---|---|---|
| `DI_*` | Drive Inverter | vehicleSpeed, gear, systemState, torqueActual, accelPedalPos |
| `BMS_*` | Battery Management System | socUI, packVoltage, packCurrent, currentUnfiltered, brickVoltages, thermalStatus |
| `ESP_*` | Electronic Stability Program | wheelSpeed, brakeTorque, stabilityControlSts2, absBrakeEvent2 |
| `RCM_*` | Restraint Control Module (IMU) | longitudinalAccel, lateralAccel, yawRate |
| `SCCM_*` | Steering Column Control Module | steeringAngle, steeringAngleSpeed |
| `VCSEC_*` | Vehicle Controller Security | TPMSData (pressure, temperature, battery voltage) |
| `VCLEFT_*` / `VCRIGHT_*` | Vehicle Controllers (Left/Right) | restraintStatus, frontOccupancyStatus, frontBuckleStatus, rideHeight, doorStatus |
| `DAS_*` | Driver Assistance System | autopilotState, forwardCollisionWarning, laneDepartureWarning, sideCollisionWarning |
| `APP_*` | Autopilot Processor | environmentRainy, environmentSnowy, cameraLux, warningMatrix |
| `UI_*` | User Interface / GPS | locationStatus (lat/lng), gpsVehicleSpeed, gpsVehicleHeading, odometer |
| `VCFRONT_*` | Vehicle Controller Front | sensors (brakeFluidLevel, coolantLevel, washerFluidLevel), tempAmbient, 12VBatteryStatus, wiperCycles |
> This is only a brief list of the collected signals. Note that signal names and data vary by automaker.

### 3.1.2 Kinesis Data Stream

On-demand data stream for real-time telemetry delivery. Configured in on-demand mode for early stages with planned transition to provisioned mode. Encrypted with KMS-managed keys and uses 24hr retention windows for data replay recovery. Vehicle identifiers provide partition keys with per-vehicle ordering and KCL checkpoints for at least once delivery. Monitored via `WriteProvisionedThroughputExceeded` and `IncomingBytes` per shard in CloudWatch.

### 3.1.3 Kinesis Data Firehose
Ingests batched telemetry records from the Telemetry Consumer Service compiled into 5KB batches to minimize Firehose billing (charged in 5KB increments). Compresses and converts batched records to Parquet format. Data is archived in S3 for long-term archival and Athena historical trend queries.

### 3.1.4 Telemetry Consumer Service (ECS Fargate)

Primary telemetry data stream processor. Pulls records from Kinesis Data Stream in batches, applies VIN pseudonymization, and fans out to multiple targets based on event type:
| Event Type | DynamoDB Target | Valkey | SQS/SNS | Firehose | InfluxDB |
|---|---|---|---|---|---|
| Vehicle state update (door status, occupancy, etc) | `vehicle-live` | PUBLISH | - | Yes | Maintenance-related data |
| Trip start/end | `vehicle-live`, `trip-history` | PUBLISH | - | Yes | - |
| Trip breadcrumb (GPS, speed, etc) | - | PUBLISH | - | Yes | - |
| Vehicle Incident Notification (crash events, unsafe driving, etc) | - | - | SNS Critical Alerts | Yes | - |
| Internal Admin Data (errors, connectivity, metrics) | - | - | - | Yes | - |

**Error handling:** The Consumer handles errors differently for each downstream target. DynamoDB and Firehose are considered critical and mandatory write targets. The Consumer will attempt to write 5 times and if they all fail, the entire batch is retried via KCL checkpoint rollback. Valkey, SQS, SNS, and InfluxDB are considered non-mandatory targets. SQS and SNS corrupted jobs are handled using DLQs. Valkey failed publishes are logged and skipped. The Consumer opens the circuit to InfluxDB if it fails to write to it 5 consecutive times. When the circuit is open, writes to InfluxDB are skipped and every 30s the Consumer attempts to reconnect to InfluxDB.

**KCL configuration:**

| Parameter | Value |
|---|---|
| KCL version | 2.x (enhanced fan-out not used) |
| Checkpoint frequency | Every 60 seconds or every 500 records, whichever comes first |
| Max records per poll | 500 |
| Idle time between polls | 1 second |
| Lease table | `{appName}-kcl-leases` (DynamoDB, on-demand) |
| Shard sync interval | 30 seconds |

---

## 3.2 Data Model

DynamoDB handles the core data with seven tables. Timestream for InfluxDB handles time-series data. Full data archives (and append-only data) are stored in S3 via Firehose.

### 3.2.1 Vehicle-Scoped Tables

| # | Table | PK | SK Pattern | Contents |
|---|---|---|---|---|
| 1 | `vehicle-live` | `pseudoVIN` | `STATE`, `TRIP#active`, `CHARGING#active`, `GEOFENCE#{geofenceId}` | Current vehicle state (overwrites only) |
| 2 | `trip-history` | `pseudoVIN` | `TRIP#{tripDate}#{tripId}` | Completed trip summaries with S3 archive references |

### 3.2.2 Organization-Scoped Tables

| # | Table | PK | SK Pattern | Contents |
|---|---|---|---|---|
| 3 | `organization` | `organizationId` | `META`, `MEMBER#{userId}`, `DRIVER#{driverId}`, `ASSIGN#{pseudoVIN}`, `ALERT#{alertId}` | All org CRUD data. GSI on SK for reverse lookups |
| 4 | `fleet-operations` | `organizationId` | `REPORT#{reportId}`, `MAINT#{pseudoVIN}#{date}`, `MAINT_ALERT#{alertId}`, `SECURITY#{configType}` | Org operational data |

### 3.2.3 Utility Tables

| # | Table | PK | SK | Purpose |
|---|---|---|---|---|
| 5 | `vin-mapping` | `pseudoVIN` | - | Bidirectional VIN<->pseudoVIN resolution. Restricted IAM access (ADR-005) |
| 6 | `command-audit` | `userId` | `{timestamp}#{pseudoVIN}` | Vehicle command audit trail. TTL: 90 days via `expiresAt` (Unix epoch: `currentEpochSeconds + 7776000`) |
| 7 | `oem-tokens` | `USER#{userId}` | `TOKEN#{pseudoVIN}` | OAuth tokens for OEM API access (per-user, per-vehicle) |

### 3.2.4 S3 Parquet Data Lake

| Data Type | S3 Partition Pattern | Retention |
|---|---|---|
| GPS breadcrumbs | `breadcrumbs/pseudoVIN/yyyy/MM/dd/HH` | 1 year, then Glacier IR |
| Telemetry events (errors, connectivity, metrics) | `telemetry-events/pseudoVIN/yyyy/MM/dd/HH` | 1 year, then Glacier IR |
| Vehicle alerts | `alerts/pseudoVIN/yyyy/MM/dd/HH` | 1 year, then Glacier IR |
| Charging session history | `charging/pseudoVIN/yyyy/MM/dd/HH` | 1 year, then Glacier IR |
| Security events | `security-events/pseudoVIN/yyyy/MM/dd/HH` | 2 years, then Glacier IR |

### 3.2.5 Tenant Isolation Enforcement

The data stores were designed with tenant data isolation in mind. Vehicle-scope tables utilize the `pseudoVIN` partition key and organization-scope tables utilize the `organizationId` partition key. When a user requests vehicle data, the API handler lambda function extracts the requester's `pseudoVIN` or `organizationId` claims from Cognito JWT. Before fulfilling the request, the function validates that the requester has the valid claim for the resource they are requesting. Validations that succeed are provided resources, otherwise are rejected with a `403` error.

---

## 3.3 Trip Processing Pipeline

### 3.3.1 Trip Detection State Machine

The Telemetry Consumer has a trip detection state machine built in. It detects trip start and end transitions from vehicle speed and driver seat occupancy.

**Configuration (SSM Parameter Store):**

| Parameter | Default | Purpose |
|---|---|---|
| `tripStartSpeedMph` | 5 mph | Speed above which a trip begins |
| `tripEndSpeedMph` | 1 mph | Speed at or below which a trip may be ending |
| `tripGapDetectionSeconds` | 300s | Duration speed must remain below end threshold to confirm trip end |

**Primary signals:**

| Signal | Source | Role |
|---|---|---|
| `DI_vehicleSpeed` | Drive Inverter | Primary trip boundary trigger |
| `VCLEFT_frontOccupancyStatus` | Vehicle Controller Left | Confirms driver presence on start and departure on end |

**State transitions:**

1. **IDLE to ACTIVE:** `vehicleSpeed` exceeds `tripStartSpeedMph` AND driver seat is occupied
   - No active trip may exist for this pseudoVIN
   - The Consumer creates a `TRIP#active` record in `vehicle-live` with `status=active`
   - Generates a unique `tripId`, and begins recording breadcrumbs
  
2. **ACTIVE to PENDING END:** `vehicleSpeed` drops below `tripEndSpeedMph`
   - The Consumer writes a `gapExpiresAt` epoch timestamp (`now + tripGapDetectionSeconds`) to the `TRIP#active` record. 
   - Breadcrumbs continue recording
  
3. **PENDING END to ACTIVE:** `vehicleSpeed` rises above `tripStartSpeedMph` before `gapExpiresAt` expires
   - The Consumer clears `gapExpiresAt` and the trip continues
  
4. **PENDING END to IDLE:** Current time exceeds `gapExpiresAt` OR driver seat is unoccupied
   - The trip is finalized and the `TRIP#active` record is closed.

**State persistence:** Trip state is written to DynamoDB as it changes, so the Consumer is stateless between restarts. On startup or shard reassignment, the Consumer queries `vehicle-live` for all `TRIP#active` records and rebuilds in-memory state from `status`, `gapExpiresAt`, `tripId`, and `lastBreadcrumbTimestamp`.

**Stale trip cleanup:** An EventBridge rule (rate: 5 minutes) triggers a Lambda that scans `vehicle-live` for `TRIP#active` records where `lastBreadcrumbTimestamp` is older than (2 x `tripGapDetectionSeconds`) (default: 10 minutes). The Lambda force finalizes orphaned trips by closing the `TRIP#active` record, writing the trip summary to `trip-history`, and uploading the breadcrumb archive to S3.


### 3.3.2 S3 Breadcrumb Archive Format

Breadcrumb archives are stored at `trips/{pseudoVIN}/{tripId}.gz` as gzipped JSON arrays. Each breadcrumb captures the full vehicle context at that very moment.

**Breadcrumb example:**

```json
[
  {
    "timestamp": "2025-03-05T14:32:01.000Z",
    "lat": 39.7392,
    "lng": -104.9903,
    "vehicleSpeed": 73.5,
    "heading": 90,
    "odometer": 22683.6,
    "batteryLevel": 75,
    "...."
  }
]
```

Detailed versions can be found in /sample-data/telemetry/breadcrumb-archive.json


### 3.3.3 Trip Processor

Generates trip summary metrics and computes analytical data from breadcrumb archives. When the Telemetry Consumer Service writes a completed trip record, the `trip-history` DynamoDB table stream invokes this function.  

**Configuration:**

| Parameter | Value |
|---|---|
| Runtime | Lambda |
| Archive size limit | 100 MB (auto-rejects larger files) |
| Idempotency | Skips job if archive has an existing `processedAt` attribute |

**Summary metrics:**

| Metric | Computation |
|---|---|
| `distanceMiles` | Sum of distances between consecutive breadcrumbs |
| `durationMinutes` | `endTime - startTime` |
| `maxSpeedMph` | Highest speed value across all breadcrumbs |
| `avgSpeedMph` | Average speed across all breadcrumbs |
| `startBattery` / `endBattery` | First and last `batteryLevel` values |
| `originLocation` / `destinationLocation` | Reverse geocodes the first and last `{lat, lng}` pairs to human-readable addresses |

**Safety event detection:**

The Trip Processor detects safety events using data from several of the vehicle's sensors. A high-level overview of the unobvious signals include:
- `RCM_longitudinalAccel` (Longitudinal Acceleration) - Measures if the vehicle is accelerating forward (positive value) or decelerating/braking/reversing (negative value)
- `RCM_lateralAccel` (Lateral Acceleration) - Measures if the vehicle is accelerating (making a turn) to the left (positive value) or to the right (negative value)
- `RCM_yawRate` - Measures the angular velocity of the vehicle more granularly
- `RCM_collision*` - Indicates that the vehicle has experienced a collision severe enough to trigger safety mechanisms
- `VCLEFT_* / VCRIGHT_*` - Provides status of occupancy and seatbelts
- `APP_environment*` - (Rainy, Snowy) Environment context signals recorded by safety sensors, these values can provide further insight to specific safety events


| Event Type | Signal Source | Detection Logic | Threshold (SSM-configurable) |
|---|---|---|---|
| Excessive speeding | `DI_vehicleSpeed` | `vehicleSpeed > speedLimitMph` | Default: 85 mph |
| Hard braking | `RCM_longitudinalAccel` | Peak deceleration exceeds threshold | Default: ≈ -0.45g |
| Hard acceleration | `RCM_longitudinalAccel` | Peak acceleration exceeds threshold | Default: ≈ 0.40g |
| Aggressive turn | `RCM_lateralAccel`, `RCM_yawRate` | Peak lateral acceleration exceeds threshold | Default: ≈ 0.40g |
| Crash detection | `RCM_collision*` | `RCM_collisionSeverity` ≥ 2 | Severity Levels: 0=none, 1=minor, 2=moderate, 3=severe |
| Seat belt violations | `VCLEFT_frontBuckleStatus`, `VCRIGHT_frontBuckleStatus`, `VCLEFT_rearLeftBuckleStatus`, `VCRIGHT_rearCenterBuckleStatus`, `VCRIGHT_rearRightBuckleStatus` | Unbuckled during active trip (rear seats gated by occupancy via `VCLEFT_rear*OccupancyStatus`) | True |

The table above contains the most reliable signals I have tested at this point. The g-force thresholds were tuned by driving in various conditions and comparing the sensor data against what I felt in the car. The hard braking threshold roughly corresponds to a panic stop from highway speed. The aggressive turn threshold catches the kind of turn that send items in the car flying. These are starting points and will need adjustment for different vehicle types and driving environments. Additional signals can be integrated such as vehicle safety system activations (emergency braking, lane departure, collision warning systems).


The trip processor calculates a composite driving score per trip using a severity-weighted point deduction system. Each detected safety event is classified as mild (2 points), moderate (5 points), or severe (10 points) based on how far the signal exceeds its detection threshold. Severity bands for each event type are SSM-configurable. Each event category (speeding, braking, acceleration, turning, seat belt, crash) has a penalty cap (15-25 points depending on category) to prevent a single category from dominating the score on long trips.

```
categoryPenalty = min(cap, sum of severity points for all events in category)

drivingScore   = max(0, 100 - sum of all category penalties)
```

For example, a trip with 3 mild speeding events (6 pts), 1 moderate hard brake (5 pts), and 1 mild hard acceleration (2 pts) scores `100 - 13 = 87`. Scores above 80 represent normal driving, 60-80 indicates aggressive patterns, 50-59 indicates elevated risk, and below 50 signals genuinely unsafe behavior.

**Final trip artifact:**

```json
{
  "pseudoVIN": "a1b2c3...",
  "tripId": "trip_20250305_143201_a1b2c3",
  "tripDate": "2025-03-05",
  "startTime": "2025-03-05T14:32:01.000Z",
  "endTime": "2025-03-05T15:04:33.000Z",
  "startLocation": { "lat": 39.7392, "lng": -104.9903, "address": "Street Name, City, State" },
  "endLocation": { "lat": 39.7456, "lng": -104.9712, "address": "Street Name, City, State" },
  "..."
  "breadcrumbCount": 1847,
  "drivingScore": 88,
  "safetyEvents": [
    { "type": "hard_braking", "timestamp": "2025-03-05T14:45:12.000Z", "lat": 39.7410, "lng": -104.9850, "severity": "moderate" }
  ],
  "s3ArchiveKey": "trips/a1b2c3.../trip_20250305_143201_a1b2c3.gz",
  "processedAt": "2025-03-05T15:05:01.000Z"
}
```
Detailed versions can be found in /sample-data/trips/completed-trip.json.

### 3.3.4 Incident & Emergency Alert Delivery

This system detects collision events from the vehicle's Restraint Control Module (RCM) sensor and delivers emergency notifications to recipients in real-time. The Telemetry Consumer Services triggers emergency notifications when it processes `RCM_collision` signals for a vehicle. Emergency notifications are delivered through a dedicated SNS topic, and the event is recorded in Firehose archive.

The `RCM_collision` signal provides further context of collision events: 

- Whether the collision impacted the left or right side of the vehicle
- Whether the collision was head-on or from the rear
- Whether the collision resulted in a rollover
- Whether airbags deployed
- Whether seatbelts were buckled
- Severity levels

Crash alert payloads contain the collision information and are further enriched with the most recent GPS ping and occupancy status from the breadcrumb stream. 

**Severity classification:**

| Value | Classification | Response Action |
|---|---|---|
| 0 | No collision | No action |
| 1 | Minor collision | Log event only, no immediate alert |
| 2 | Moderate collision | Alert fleet operator |
| 3 | Severe collision | Alert fleet operator AND driver's emergency contact |


The intention of this system was to simply notify recipients of critical collision incidents. However, this system can also make a great tool to analyze collision events using source of truth data. Supplemental signals such as the vehicle speed, acceleration/brake pedal positions, and steering wheel angles can also be collected to accurately recreate the driver's exact reaction.

---

## 3.4 Geofence Evaluator

This system allows the user to define geofencing boundaries and receive notifications upon boundary crossing events. As breadcrumbs are created, the Consumer provides the SQS Geofence Check Queue with the vehicle's GPS location. The Geofence Evaluator lambda function pulls from the queue, loads geofence definitions from the `fleet-operations` table and evaluates each breadcrumb against them. Boundaries are stored as GeoJSON polygons and checked using ray casting (point-in-polygon). Previous geofence state is tracked in `vehicle-live` under `GEOFENCE#{geofenceId}` sort keys to detect enter/exit transitions. The queue was specifically created in `FIFO` mode to prevent corruption from out of order event processing. Additionally, the `pseudoVIN` is the message group ID to prevent cross-vehicle processing errors. If geofence cross events are detected the state transition in `vehicle-live` is updated and an alert is sent through SNS.

> Geofence evaluator is based on this blog post and tutorial here, [Ray Casting Algorithm](https://philliplemons.com/posts/ray-casting-algorithm) by Phillip Lemons.


**Configuration:**
| Parameter | Value |
|---|---|
| Runtime | Lambda (Python) |
| Queue type | FIFO with `pseudoVIN` message group ID |
| Visibility timeout | 30 seconds |
| Deduplication | `MessageDeduplicationId` = `{pseudoVIN}#{timestamp}` |

---


## 3.5 Dashcam Processor

This system integrates dashcam cameras with the platform and automatically uploads footage to AWS. The Edge Device compiles clips into a single zip file and uploads it directly to S3 under `/raw/{pseudoVIN}/{eventTimestamp}`. An S3 notification triggers EventBridge, which enqueues the job to the Dashcam Processor SQS queue. The Dashcam Processor Lambda fetches and unzips the archive, transcodes clips to web-optimized format, and extracts thumbnails. Two output artifacts are produced:

1. Original footage moved to `/archive/{pseudoVIN}/{eventTimestamp}`
2. Compressed web-optimized version written to `/web/{pseudoVIN}/{eventTimestamp}`
  
The raw zip is deleted from `/raw/` once processing completes.

**S3 path reference:**

- `/raw/` - Landing zone for unprocessed uploads
- `/archive/` - Original uncompressed footage
- `/web/` - Compressed web-optimized footage for playback 

**Configuration:**

| Parameter | Value |
|---|---|
| Runtime | Lambda (Python) |
| Input validation | Rejects oversized clips |
| Clip length | 30s (default) |

**S3 lifecycle:**

| Stage | Path | Retention |
|---|---|---|
| Raw footage | `raw/` | Deleted after processing |
| Compressed (web-optimized) | `web/` | 90 days Standard, then Intelligent-Tiering |
| Archive | `archive/` | Intelligent-Tiering to Glacier IR at 180 days |

### 3.5.1 Edge-Side Clip Retrieval

I have tested using a second Edge Device paired with the dashcam. The device emulates a standard USB storage device from the dashcam's perspective, giving it full control over footage files as they are written. The key insight is that the dashcam doesn't know the difference between its own storage and the Edge Device, it just writes files. This means clips can be copied without interrupting active recordings, and since the Edge Device controls the storage layer directly, clip deletion by the driver is effectively impossible. IoT Core sends MQTT commands to this device with the event timestamp. The device copies the clip files, zips them without interrupting active recordings. The zip file is uploaded to S3 and follows the standard processing path above.

This enables the Telemetry Consumer Service to detect specific events and trigger IoT Core to issue retrieval commands. Use cases of this may include crash events, seatbelt violations, speeding, and other safety events. Clips are collected without any input from the driver or camera, and since the Edge Device controls the storage layer directly, clip deletion essentially becomes tamperproof.


---

## 3.6 Supporting Services

### 3.6.1 OEM Command Proxy

This function is responsible for performing a final ownership validation check and securely transmitting commands to the OEM API endpoint. The function validates vehicle ownership by verifying the `pseudoVIN` against the caller's JWT claim set. If validated, it constructs the command payload and signs it using an OEM-trusted private key from Secrets Manager (or cache). The command payload is forwarded to the OEM API endpoint through the NAT gateway. Every command writes an audit record to `command-audit` with the `userId`, `pseudoVIN`, command type, result, and timestamp.

**Configuration:**

| Parameter | Value |
|---|---|
| Runtime | Lambda (Go) |
| Timeout | 10 seconds |
| Key cache invalidation | EventBridge rule on Secrets Manager rotation events |


### 3.6.2 Real-Time Streaming Service

The SSE Streaming Service is hosted on ECS Fargate and streams live vehicle updates to browser clients through Server-Sent Events (SSE). The SSE Streaming Service subscribes to ElastiCache Valkey's channel to receive live events. A network load balancer is deployed in the public subnet to connect the service to CloudFront using port 3000. 

**Initial Connection Establishment**
1. The SSE Streaming Service fetches and extracts `pseudoVIN` from the user's JWT claims
2. Validations checks are done to ensure that the caller's claims match the requested vehicle's `pseudoVIN`
3. If successful, the SSE Streaming service immediately retrieves the latest vehicle snapshot from DynamoDB while the Valkey subscription is being made
4. Valkey channels are unsubscribed on client disconnect

The SSE Streaming Service was built to gracefully terminate and auto reconnect clients. Upon interruption or failure, ECS Fargate handles deploying a new task automatically. In the time between the task failing and starting back up, the client falls back to DynamoDB polling within 5s. When the new task is active, the service reconnects to the clients. From the user's perspective there is no break or visible delay in their dashboard.

Given the stateless and auto recover capabilities, it made sense to configure the service in Spot capacity mode to optimize costs. More info on the rationale can be found in *ADR-003.*

TLS termination happens at the NLB on port 443 using an ACM certificate, with a legacy TCP:3000 listener retained as a fallback for environments without a certificate (dev). CloudFront connects to the NLB over HTTPS.

**Configuration:**

| Parameter | Value |
|---|---|
| Runtime | ECS Fargate Spot |
| Load balancer | NLB, TLS:443 (falls back to TCP:3000 when no ACM cert) |

**DynamoDB Polling configuration:**

| Parameter | Value |
|---|---|
| Poll interval | 5 seconds |
| Read pattern | `GetItem` on `vehicle-live` by `pseudoVIN` |
| Reconnect behavior | Exponential backoff: 1s start, 30s max, with jitter |
| Polling scope | Only vehicles on the active dashboard tab |

### 3.6.3 Predictive Maintenance Analytics

This system is built on Timestream for InfluxDB and computes analytics on the health of major vehicle components over time. The Telemetry Consumer Service routes selective data (found below) to InfluxDB via Line Protocol. Analysis is conducted by the Predictive Maintenance Analysis lambda function by running flux queries via HTTP API. This analysis is scheduled to run once an hour and is invoked by EventBridge. When potential service-related issues are discovered, maintenance alerts are sent through SNS and the `fleet-operations` table is updated with the maintenance alert. 

**Configuration:**

| Parameter | Value |
|---|---|
| Instance | `db.influx.medium`, Single-AZ, private subnet |
| Port | 8086  |
| Authentication | InfluxDB API tokens stored in Secrets Manager |
| Retention | 90-365d across 9 dedicated buckets |
| Analysis Lambda | 512 MB, 30s timeout |
| Analysis schedule | 1h (EventBridge) |


**InfluxDB bucket design:**
| Bucket | DBC Signals | Insights |
|---|---|---|
| `battery_telemetry` | `BMS_brickVoltages`, `BMS_packVoltage`, `BMS_currentUnfiltered`, `BMS_socMin`/`BMS_socUI`, `BMS_nominalFullPackEnergy`/`BMS_idealRemainEnergy`, `BMS_thermalStatus`, `BMS_bmbMinMax` | Detects major deviations of battery voltage or capacity that drift from baseline trends |
| `charging_sessions` | `BMS_chargerRequest`, `BMS_kwhCounter`, `BMS_kwhCountersMultiplexed`, `BMS_chgTimeToFull` | Track charging session trends to detect abnormal charging session times |
| `drivetrain_metrics` | `DI_temperature`, `DI_torqueActual`, `DI_torqueCommand`, `DI_axleSpeed`, `DI_systemPower`, `DI_frontTemperature` | Compare torque and thermal temperature against baseline trends to detect mechanical or cooling discrepancies |
| `tire_pressure` | `VCSEC_TPMSData` | Per-tire pressure monitoring |
| `steering_health` | `EPAS3P_torsionBarTorque` | Tracks steering power data  |
| `thermal_management` | `BMS_powerDissipation`/`BMS_flowRequest`, `VCFRONT_compressorState`/`VCFRONT_pumpBatteryRPMActual`/`VCFRONT_radiatorFanRPMActual` | Tracks data from the battery thermal system and HVAC |
| `suspension_health` | `VCLEFT_frontRideHeight`/`VCLEFT_rearRideHeight`| Detect ride height deviation for suspension health |
| `fluid_levels` | `VCFRONT_brakeFluidLevel`, `VCFRONT_coolantLevel`, `VCFRONT_washerFluidLevel` | Tracks fluid levels of the vehicle |
| `vehicle_maintenance` | `VCFRONT_wiperCycles` | Tracks the amount of times a wiper is cycled |

**Flux query patterns:**
The Lambda function runs Flux queries against each bucket using standard deviation anomaly detection. It computes the mean and standard deviation of the data over a period of time, and flag vehicles whose readings exceed a configurable threshold. The windows of time vary by each bucket, for example, `tire_pressure` is usually something you'd track daily, while `battery_telemetry` is something you'd track for at least 60+ days.

Example for `tire_pressure` (flags readings > 2σ from the vehicle's 24-hour mean):

```flux
from(bucket: "tire_pressure")
  |> range(start: -1d)
  |> filter(fn: (r) => r._measurement == "tpms" and r._field == "pressure_psi")
  |> group(columns: ["pseudoVIN", "tire_position"])
  |> reduce(
       fn: (r, accumulator) => ({
         count: accumulator.count + 1.0,
         sum:   accumulator.sum + r._value,
         sumSq: accumulator.sumSq + r._value * r._value,
         last:  r._value
       }),
       identity: {count: 0.0, sum: 0.0, sumSq: 0.0, last: 0.0}
     )
  |> map(fn: (r) => ({
       r with
       mean:   r.sum / r.count,
       stddev: math.sqrt(x: (r.sumSq / r.count) - (r.sum / r.count) * (r.sum / r.count))
     }))
  |> filter(fn: (r) => math.abs(x: r.last - r.mean) > 2.0 * r.stddev)
```
> More info on this flux query can be found here, [Detecting Anomalies in Time Series](https://blog.davidvassallo.me/2021/09/28/influxdb-flux-detecting-anomalies-in-time-series/) by David Vassallo. 


### 3.6.4 Access Token Service

The Access Token lambda functions are responsible for assigning temporary access tokens for specific resources and validating subsequent requests using the tokens. This is primarily used for access to sensitive user data or assets such as dashcam media or organization fleet reports. 

**Token Generator:**

| Parameter | Value |
|---|---|
| Runtime | Lambda |
| Token expiration | 15 minutes |
| Signing | HMAC-SHA256 signed JWTs payloads: `pseudoVIN`, `resourceType`, `exp` (15-min TTL), `iat` |
| CloudFront key pair | An RSA-2048 public key is uploaded to CloudFront trusted key groups. The private key is stored in Secrets Manager and retrieved by the Token Generator Lambda. Signed URLs use CloudFront canned policy. |
| Ownership verification | Validates `pseudoVIN` against caller's JWT claims |

**Token Authorizer:**

| Parameter | Value |
|---|---|
| Validation | Token signature, expiration, and resource scope |
| Cache | API Gateway Lambda authorizer result caching with 5-minute TTL (cache key: authorization token value) |

---
[AWS Environment Design](02-aws-environment-design.md) | [Next: Security and Resilience](04-security-and-resilience.md)
