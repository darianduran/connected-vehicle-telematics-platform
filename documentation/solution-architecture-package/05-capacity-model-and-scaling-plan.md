# 5.0 Capacity Model and Scaling Plan

## 5.1 Load Assumptions and Traffic Model

All performance targets and capacity models in this document are based on the following assumptions:

| Parameter | Value | Source |
|---|---|---|
| Fleet size (design ceiling) | 10,000 vehicles | Cost analysis fleet projections |
| Events per vehicle | ~1 event/15 sec (active) | Detailed Component Design (3.1.1) |
| Active vehicle percentage | ~100% during peak hours | Uniform distribution assumed |
| Steady-state event rate | ~656 events/sec | 10K vehicles x 1 event/15 sec |
| Peak-to-average ratio | 5x | BR-1 burst scenario |
| Peak event rate | ~5,000 events/sec | Fleet reconnection storm |
| Average event size | ~1 KB | Detailed Component Design (3.1.2) |

> This assumes that each vehicle produces the exact same traffic, predicting traffic is nearly impossible. Real-world traffic baselining needs to be done to refine this model.

---

## 5.2 Performance SLAs

| Metric | Typical | SLA Limit | Measurement Path |
|---|---|---|---|
| API response latency | < 200ms | < 3s | API Gateway to client |
| End-to-end telemetry persistence | < 500ms | < 5s | Vehicle event to DynamoDB write |
| Dashboard update latency | < 1s | < 5s | Vehicle event (IoT Core) to browser render |
| Trip detection latency | < 5s | < 1m | Drive state change to trip record creation |
| Vehicle command round-trip | < 3s | < 10s | User action to OEM API response |

> **Note:**
> - *Typical* refers to the expected and normal processing time
> - *SLA Limit* refers to the processing time in which warrants investigation
> - *End-to-end telemetry persistence* metric starts when data reaches IoT Core (not from the vehicle itself).
> - These are used as targets to align with for healthy operations, not contractual SLAs

---

## 5.3 Scalability Strategy

### 5.3.1 Telemetry Ingestion (Kinesis)
Kinesis is configured with on-demand mode to auto provision shards based on throughput. Provisioned mode is more cost-effective but has key considerations before transitioning. The platform must formally baseline normal operations to understand the traffic demands day-to-day. The platform must also have controls in place to scale beyond the provisioned capacity in the event of large-scale outages. In such events, thousands of vehicles buffer hundreds of events offline until the services recover, reconnect simultaneously and flush their local buffers. 

On-demand mode allows the platform to mature to discover normal baseline and recover seamlessly during potential larger-scale outages.

### 5.3.2 Database (DynamoDB)

All 7 DynamoDB tables use on-demand mode to scale automatically. Provisioned mode is not worth transitioning to until the platform scales much larger.

### 5.3.3 Compute - Telemetry Consumer Service

The Telemetry Consumer Service is the most compute demanding service due to concurrent fan out across multiple targets.

| Parameter | Value |
|---|---|
| CPU / Memory | 1024 / 2048 MB |
| Steady state load (10K fleet) | ~50% CPU |
| Scaling trigger | > 70% CPU sustained for 5 min |

The service is configured to scale out when CPU usage exceeds 70% for 5 min. If a task experiences failure before the scaling trigger kicks in, it will cause a few minutes of delayed processing and latency. Since the Kinesis Data Stream retains 24h of records, there will be no data loss. At scale the service runs 3 tasks concurrently, so the risk of a single task failure causing significant impact is low and will not result in data loss.


### 5.3.4 Compute - SSE Streaming Service

| Parameter | Value |
|---|---|
| CPU / Memory | 256 / 512 MB |
| Steady-state load | ~40% CPU per 1K connections |
| Primary scaling target | 1,000 active connections per task |
| Secondary scaling trigger | > 70% CPU sustained for 5 min |
| Capacity ceiling per task | ~1,500 connections before memory pressure |

The SSE Streaming Service is lightweight and does not require higher resource allocation. The only constraint is in maintaining many open connections at a given time. The production runtime configuration aligns with a 1000 connection target. This target is very excessive to provide headroom for reconnection bursts such as reconnection storms.

### 5.3.5 Timestream for InfluxDB

| Parameter | Value |
|---|---|
| Instance | db.influx.medium (1 vCPU, 8 GiB RAM) |
| Steady-state write rate | ~131 writes/sec (selective routing at 10K vehicles) |
| Scaling trigger | Sustained > 80% CPU, scale to db.influx.large (2 vCPU, 16 GiB RAM) |
| Monitoring metric | `CPUUtilization` in CloudWatch |

AWS categorizes the instance `db.influx.medium` as a non-production instance, however, its role in the platform is low demand. Accepting the weaker specification instance is acceptable to save on costs. In the event of Timestream or instance failure, the Consumer simply closes the connection to it and reopens it once it recovers. The data collected and processed by Timestream is a non-critical workflow.

---
[Security and Resilience](04-security-and-resilience.md) | [Next: Deployment and Operations Playbook](06-deployment-and-operations-playbook.md)
