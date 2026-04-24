# Connected Vehicle Telematics Platform - AWS Architecture

> Author: Darian Duran | [LinkedIn](https://linkedin.com/in/darianduran)


This project contains a complete solution architecture documentation package for a vehicle telematics platform built on AWS. It started as a personal project to control my car remotely but eventually turned into a full telematics solution. 

The architecture and documentation are structured the way I'd deliver a real production deployment but with cost efficiency suitable for smaller organizations or individual owners. All documentation including diagrams and architecture decision records (ADRs) can be found in the `documentation/` directory. Terraform infrastructure code (IaC) is included in the `iac/` directory. Real examples of processed data can be found in the `sample-data/` directory.

> **Note:** 
> - The solution architecture documentation reflects the full platform design.
> - Terraform IaC is being finalized and expected to release shortly
> - Edge Device installation guide and additional demos will follow after.

---

## Vehicle Telematics Background

Every modern vehicle is built with dozens of sensors and components that are constantly generating data. This includes data from the engine/battery, drive train, safety systems, and more. This data is exchanged internally between major components through the vehicle's CAN bus. By installing a small device that taps into the CAN bus, you can capture data stream and relay it to the cloud for processing.

Telematics is the process of collecting vehicle generated data to derive meaningful insights.

---

## Solution Overview

The platform gives fleet operators and vehicle owners a centralized dashboard that updates in real-time as vehicles emit data. Users can track vehicle locations on a live map, replay completed trips with full route history, review driving behavior scores, and send remote commands to their vehicles.

In the background, the platform is constantly analyzing incoming data. It detects events like crashes and geofence boundary crossings and delivers alerts immediately without waiting for someone to check a screen. Dashcam footage is automatically captured and linked to specific driving events for review. Months of vehicle component data are aggregated and analyzed to flag potential service issues before they escalate.


---

## Architecture Overview

The platform is built entirely on AWS using managed services wherever possible. Vehicles transmit telemetry over MQTT to AWS IoT Core. From there, data flows through Kinesis into a consumer service that pseudonymizes vehicle identifiers, persists state to DynamoDB, archives to S3 via Firehose, and publishes live updates through ElastiCache Valkey to the SSE streaming service. Dashboards update within seconds of the vehicle generating the data.

![Executive Architecture Diagram](documentation/diagrams/aws-executive-diagram.png)

### Key Design Highlights

| Highlight | Summary |
|---|---|
| Subsecond ingestion | IoT Core to Kinesis to consumer service pipeline with per-vehicle ordering |
| Live dashboards | Valkey pub/sub to SSE with automatic DynamoDB polling fallback if the stream drops |
| Multi-tenant isolation | Cognito JWT claims enforce data separation at the API and data store level |
| PII protection | VINs are pseudonymized at the ingestion boundary before reaching any data store |
| Cost-optimized | Runs under $400/mo at 100 vehicles. Architecture decisions documented in ADRs have continuously driven costs down |
| Reliable fallbacks | Every core workflow has a degradation path. Nothing goes fully offline from a single component failure |


---

## Solution Architecture Documentation

The documentation package is structured as a series of documents that progressively detail the platform from business context through to operational support. Each document is written to be read independently or as part of the full package.

| Document | What It Covers |
|---|---|
| [Project Overview and Scope](documentation/solution-architecture-package/01-project-overview-and-scope.md) | Background, problem statement, platform summary, capabilities, and business/functional/non-functional/technical requirements |
| [AWS Environment Design](documentation/solution-architecture-package/02-aws-environment-design.md) | Component architecture, data flows, network design, and defense-in-depth model |
| [Detailed Component Design](documentation/solution-architecture-package/03-detailed-component-design.md) | Service-level design for ingestion, data model, trip processing, geofencing, dashcam, and supporting services |
| [Security and Resilience](documentation/solution-architecture-package/04-security-and-resilience.md) | Data protection, IAM, logging, key management, recovery objectives, and failover procedures |
| [Capacity Model and Scaling Plan](documentation/solution-architecture-package/05-capacity-model-and-scaling-plan.md) | Load modeling, throughput estimates, and scalability strategy |
| [Deployment and Operations Playbook](documentation/solution-architecture-package/06-deployment-and-operations-playbook.md) | Infrastructure-as-code strategy, release strategies, and observability |
| [Cost Model](documentation/solution-architecture-package/07-cost-model.md) | Per-service cost estimates, optimization strategies, and environment comparison |

---

## Architecture Decision Records

Key architectural choices are documented as ADRs. Each record captures the context, options evaluated, and rationale behind the decision.

| ADR | Decision | Status |
|---|---|---|
| [ADR-001](documentation/architecture-decision-records/001-fargate-over-eks.md) | ECS Fargate over EKS for container orchestration | Accepted |
| [ADR-002](documentation/architecture-decision-records/002-kinesis-over-msk.md) | Kinesis Data Streams over MSK for telemetry ingestion | Accepted |
| [ADR-003](documentation/architecture-decision-records/003-fargate-spot-for-sse-streaming-service.md) | Fargate Spot for interruptible SSE workload | Accepted |
| [ADR-004](documentation/architecture-decision-records/004-iot-core-replaces-telemetry-server.md) | IoT Core replaces ECS Fargate Telemetry Server for ingestion | Accepted |
| [ADR-005](documentation/architecture-decision-records/005-vin-pseudonymization.md) | HMAC-SHA256 pseudonymization to protect PII | Accepted |
| [ADR-006](documentation/architecture-decision-records/006-firehose-archival-and-kinesis-retention-reduction.md) | Kinesis Data Firehose for archival and reduced stream retention | Accepted |
| [ADR-007](documentation/architecture-decision-records/007-sse-pubsub-selection.md) | ElastiCache Valkey over Redis OSS and IoT Core for SSE pub/sub | Accepted |
| [ADR-008](documentation/architecture-decision-records/008-nlb-for-sse-streaming-service.md) | Retain NLB for SSE Streaming Service over API Gateway alternatives | Accepted |
| [ADR-009](documentation/architecture-decision-records/009-datastore-evaluation.md) | DynamoDB table consolidation with hybrid S3 Parquet data lake | Accepted |
| [ADR-010](documentation/architecture-decision-records/010-single-region-with-dynamodb-cross-region-dr.md) | Single-region compute with cross-region data store replication | Accepted |
| [ADR-011](documentation/architecture-decision-records/011-iot-core-over-fleetwise.md) | IoT Core over AWS IoT FleetWise for telemetry ingestion | Accepted |
| [ADR-012](documentation/architecture-decision-records/012-influxdb-predictive-maintenance.md) | InfluxDB for predictive maintenance analytics | Accepted |

---

## Sample Data

| File | Description |
|---|---|
| [breadcrumb-archive.json](sample-data/telemetry/breadcrumb-archive.json) | Archived telemetry breadcrumb data from Firehose |
| [mqtt-payload.json](sample-data/telemetry/mqtt-payload.json) | Raw MQTT payload as received by IoT Core |
| [completed-trip.json](sample-data/trips/completed-trip.json) | Processed trip record after pipeline completion |
