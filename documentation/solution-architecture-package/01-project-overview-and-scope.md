# 1.0 Project Overview and Scope

## 1.1 Origin Context

This solution started as a simple personal project to control my vehicle remotely from any device. I wanted to be able to lock/unlock doors, and control HVAC through commands without being tied to the manufacturer's app. As I built it out, I became interested in the data that the vehicle was generating behind the scenes. Processing that data allowed me to build a full telematics platform capable of tracking vehicle data in real-time and delivering meaningful insights to owners.

## 1.2 Problem Statement

Most fleet management solutions providing the same functionality are locked behind expensive monthly subscriptions with proprietary hardware. Individual owners and smaller organizations have no realistic way to access the same visibility and control that enterprise solutions have. I wanted to build a solution that was able to match functionality with full ownership of my own data, and cheaper infrastructure costs.

## 1.3 Platform Overview

The solution starts with the vehicles themselves. Every modern vehicle constantly generates loads of data that it uses to share information between its internal systems. By installing small devices in each vehicle, we can capture that data and securely transmit it to AWS. As it reaches AWS, that data is processed and powers key workflows for users in the platform.

The platform gives fleet operators and vehicle owners a centralized dashboard used to manage their vehicles. The dashboard updates in real-time as new data are processed, providing users live visibility into their entire fleet.

In the background, the platform is also analyzing data to deliver meaningful insights to users. Data collection and correlation allow users to monitor their driver's behavior and safety level. Vehicle component data is tracked over time to help users spot service-related issues before they escalate. In the event of major incidents, such as detected crashes, the platform sends real-time notifications so users can respond immediately.


At a high-level, these are the main features provided through the solution:

- Real-time vehicle tracking and live map
- Trip analytics with full route replay
- Driver behavior scoring for unsafe driving patterns
- Crash detection and emergency notification
- Geofence monitoring with configurable enter/exit alerts
- Dashcam footage capture linked to driving events
- Remote vehicle command execution with cryptographic signing
- Predictive maintenance analytics
- Charging efficiency tracking
- Long-term historical trend analysis

*Figure 1: C4 Level 1 - System Context Diagram*
![C4 Level 1 - System Context Diagram](../diagrams/c4-level-1-diagram.png)

## 1.4 Architecture Overview

The architecture is built completely on AWS. The platform prioritizes managed services over self-managed infrastructure to minimize admin overhead. The executive diagram provides a high-level view into how AWS services connect to support platform workflows.

*Figure 2: Executive Architecture Diagram*
![Executive Architecture Diagram](../diagrams/aws-executive-diagram.png)

## 1.5 Platform Capabilities

The architecture delivers a fleet telematics platform with enterprise-like features at a cost affordable to individuals or smaller organizations. At 100 vehicles the platform runs under $400/month, compared to most solutions that would easily exceed $1000+. As vehicle count scales, the cost scales with it, 1,000 vehicles would cost around $600/month.

All vehicle data lives in your AWS account. No third party vendor has access or processes it. You control retention, deletion, and who can see it. The platform also masks vehicle identifiers at the ingestion boundary before data ever reaches a data store, so PII data like VINs are never exposed.

Crash detection, geofence violations, and unsafe driving patterns trigger immediate notifications so users can respond in real-time. Potential service-related issues are communicated to the user to prevent vehicle downtime.

The platform works with any vehicle that exposes CAN bus data through a standard OBD-II port. There's no proprietary hardware requirement and no manufacturer lock-in. The infrastructure is built entirely on managed AWS services, keeping admin overhead low and avoiding dependency on any single vendor's ecosystem.

## 1.6 Business Requirements

| ID | Requirement | Description | Measurement |
|----|-------------|-------------|-------------|
| BR-1 | Telemetry Ingestion | Ingest telemetry data with low latency persistence | Events persisted within target of NFR-2. |
| BR-2 | Real-Time Vehicle Tracking | Provide live vehicle location and status updates on a dashboard map. | Dashboard reflects the vehicle's latest state within the target of NFR-3. |
| BR-3 | Geofence Monitoring | Real-time geofence monitoring and alert notifications for boundary cross events. | Alert delivery within 2min of event. |
| BR-4 | Driver Behavior Scoring | Compute a driver safety composite score (0-100) per trip using vehicle telemetry signals. | Score computed for all completed trips.|
| BR-5 | Remote Vehicle Commands | Support sending remote commands to vehicles. | User action to command acknowledgement per NFR-4. |
| BR-6 | Dashcam Media Management | Support secure dashcam capture, upload, and retrieval via signed URLs. | Latency between the time dashcam footage is uploaded and is available is tracked. |

---

## 1.7 Non-Functional Requirements

### 1.7.1 Performance

| ID | Requirement | Target | Measurement |
|----|-------------|--------|-------------|
| NFR-1 | API response latency | < 3s | API Gateway to client |
| NFR-2 | Telemetry persistence latency | < 5s | Vehicle event to database writes |
| NFR-3 | Dashboard update latency | < 5s | Vehicle event to dashboard update |
| NFR-4 | Vehicle command round-trip | < 10s | User action to OEM API response |

### 1.7.2 Availability

| ID | Requirement | Description |
|----|-------------|-------------|
| NFR-5 | Target Availability | 99.9% availability for API and dashboard. |
| NFR-6 | Graceful SSE Degradation | Dashboard reverts to the backup live update system within 5sec of degradation. |
| NFR-7 | Async Fault Tolerance | Failed jobs are captured in a DLQ and can be debugged or reprocessed without interrupting other jobs. |

---

## 1.8 Functional Requirements

### 1.8.1 Data Ingestion

| ID | Requirement | Description |
|----|-------------|-------------|
| FR-1 | Authenticated Device Ingestion | Vehicles must mutually authenticate before communication is accepted. |
| FR-2 | Durable Streaming | Ingestion pipeline must provide short-term retention for crash recovery and long-term retention archives for permanent storage. |
| FR-3 | Malformed Message Handling | Errored telemetry records are routed to a dead-letter store and prevent pipeline blockage. |

### 1.8.2 Real-Time Data Delivery

| ID | Requirement | Description |
|----|-------------|-------------|
| FR-4 | SSE with Polling Fallback | Dashboard receives live updates via SSE with automatic fallback to polling per NFR-6. |

### 1.8.3 Authentication and Authorization

| ID | Requirement | Description |
|----|-------------|-------------|
| FR-5 | JWT Authentication | API requests authenticated via JWTs with custom claims for role and authorized vehicles. |
| FR-6 | Vehicle Command Authorization | Vehicle ownership is validated through JWT claims before remote commands are authorized. |
| FR-7 | Restricted Sensitive Media Access | Sensitive media (e.g. dashcam footage) require a temporary token (15min expiry) issued after ownership verification. |

### 1.8.4 Processing

| ID | Requirement | Description |
|----|-------------|-------------|
| FR-8 | Trip Detection | Automatically create and record trip records through telemetry signal start/end criteria. |
| FR-9 | Geofence Evaluation | Track vehicle positions against user defined geofences and alert on crossing events. |
| FR-10 | Driver Score Computation | Compute per-trip driver behavior scores from safety event signals. |

---

## 1.9 Technical Requirements

| ID | Requirement | Description |
|----|-------------|-------------|
| TR-1 | Encryption in Transit | All communications use TLS. |
| TR-2 | Encryption at Rest | All data stores use encryption at rest. |
| TR-3 | Structured Logging | All services emit structured JSON logs with correlation IDs for request tracing. |
| TR-4 | Sensitive Data | Secrets and tokens must never appear in logs. PII is pseudonymized to limit exposure. |
| TR-5 | Alerting | Critical system failures trigger alerts. Failed alert deliveries are captured for retry. |

---
[Next: AWS Environment Design](02-aws-environment-design.md)
