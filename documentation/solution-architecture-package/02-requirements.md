# 2.0 Requirements

## 2.1 Business Requirements

| ID | Requirement | Description | Measurement |
|----|-------------|-------------|-------------|
| BR-1 | Telemetry Ingestion | Ingest telemetry data with low latency persistence | Events persisted within target of NFR-2. |
| BR-2 | Real-Time Vehicle Tracking | Provide live vehicle location and status updates on a dashboard map. | Dashboard reflects the vehicle's latest state within the target of NFR-3. |
| BR-3 | Geofence Monitoring | Real-time geofence monitoring and alert notifications for boundary cross events. | Alert delivery within 2min of event. |
| BR-4 | Driver Behavior Scoring | Compute a driver safety composite score (0-100) per trip using vehicle telemetry signals. | Score computed for all completed trips.|
| BR-5 | Remote Vehicle Commands | Support sending remote commands to vehicles. | User action to command acknowledgement per NFR-4. |
| BR-6 | Dashcam Media Management | Support secure dashcam capture, upload, and retrieval via signed URLs. | Latency between the time dashcam footage is uploaded and is available is tracked. |

---

## 2.2 Non-Functional Requirements

### 2.2.1 Performance

| ID | Requirement | Target | Measurement |
|----|-------------|--------|-------------|
| NFR-1 | API response latency | < 3s | API Gateway to client |
| NFR-2 | Telemetry persistence latency | < 5s | Vehicle event to database writes |
| NFR-3 | Dashboard update latency | < 5s | Vehicle event to dashboard update |
| NFR-4 | Vehicle command round-trip | < 10s | User action to OEM API response |

### 2.2.2 Availability

| ID | Requirement | Description |
|----|-------------|-------------|
| NFR-5 | Target Availability | 99.9% availability for API and dashboard. |
| NFR-6 | Graceful SSE Degradation | Dashboard reverts to the backup live update system within 5sec of degradation. |
| NFR-7 | Async Fault Tolerance | Failed jobs are captured in a DLQ and can be debugged or reprocessed without interrupting other jobs. |

---

## 2.3 Functional Requirements

### 2.3.1 Data Ingestion

| ID | Requirement | Description |
|----|-------------|-------------|
| FR-1 | Authenticated Device Ingestion | Vehicles must mutually authenticate before communication is accepted. |
| FR-2 | Durable Streaming | Ingestion pipeline must provide short-term retention for crash recovery and long-term retention archives for permanent storage. |
| FR-3 | Malformed Message Handling | Errored telemetry records are routed to a dead-letter store and prevent pipeline blockage. |

### 2.3.2 Real-Time Data Delivery

| ID | Requirement | Description |
|----|-------------|-------------|
| FR-4 | SSE with Polling Fallback | Dashboard receives live updates via SSE with automatic fallback to polling per NFR-6. |

### 2.3.3 Authentication and Authorization

| ID | Requirement | Description |
|----|-------------|-------------|
| FR-5 | JWT Authentication | API requests authenticated via JWTs with custom claims for role and authorized vehicles. |
| FR-6 | Vehicle Command Authorization | Vehicle ownership is validated through JWT claims before remote commands are authorized. |
| FR-7 | Restricted Sensitive Media Access | Sensitive media (e.g. dashcam footage) require a temporary token (15min expiry) issued after ownership verification. |

### 2.3.4 Processing

| ID | Requirement | Description |
|----|-------------|-------------|
| FR-8 | Trip Detection | Automatically create and record trip records through telemetry signal start/end criteria. |
| FR-9 | Geofence Evaluation | Track vehicle positions against user defined geofences and alert on crossing events. |
| FR-10 | Driver Score Computation | Compute per-trip driver behavior scores from safety event signals. |

---

## 2.4 Technical Requirements

| ID | Requirement | Description |
|----|-------------|-------------|
| TR-1 | Encryption in Transit | All communications use TLS. |
| TR-2 | Encryption at Rest | All data stores use encryption at rest. |
| TR-3 | Structured Logging | All services emit structured JSON logs with correlation IDs for request tracing. |
| TR-4 | Sensitive Data | Secrets and tokens must never appear in logs. PII is pseudonymized to limit exposure. |
| TR-5 | Alerting | Critical system failures trigger alerts. Failed alert deliveries are captured for retry. |

---
[Executive Overview](01-executive-overview.md) | [Next: Solution Architecture](03-solution-architecture.md)