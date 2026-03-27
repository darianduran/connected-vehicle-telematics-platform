# 7.0 Resilience & Disaster Recovery

## 7.1 Business Impact Analysis

### 7.1.1 Tiered Recovery Objectives

| Tier | Scope | RTO | RPO |
|---|---|---|---|
| Tier 0 - Safety-Critical | Geofence alerts, collision detection, critical vehicle alerts (SNS) | < 2 min | Near-zero |
| Tier 1 - Real-Time Telemetry | IoT Core ingestion, Kinesis streaming, Telemetry Consumer Service, Valkey, SSE Streaming Service | < 5 min | Near-zero / Valkey and SSE Streaming Service only if DynamoDB polling fails |
| Tier 2 - Operational APIs and Processing | API Gateway, Lambda functions, Cognito, trip processing, vehicle commands, DynamoDB reads/writes | < 15 min | Near-zero (DynamoDB Global Tables) / < 5 min (other) |
| Tier 3 - Async Processing and Media | Trip analytics, dashcam processing, fleet reports, geofence batch evaluation, EventBridge jobs | < 1 hour | < 1 hour |
| Tier 4 - Analytics and Enrichment | Athena queries, Location Services, fleet analytics dashboards | < 4 hours | < 24 hours |
| Full Region Failover | All services, us-east-1 to us-west-2 | < 1.5 hours | < 5 min (DynamoDB) / near-zero (S3 with CRR) / < 24 hours (S3 without CRR) |



### 7.1.2 Component-to-Tier Mapping

| Component | Tier | Recovery Mechanism | Auto-Recovery | Notes |
|---|---|---|---|---|
| SNS alert topics (geofence, collision) | 0 | Multi-AZ managed service | Yes | DLQ captures failed deliveries |
| IoT Core | 1 | Multi-AZ managed service | Yes | Edge devices buffer offline during outage |
| Kinesis Data Streams | 1 | Multi-AZ managed service + 24hr retention | Yes | Consumer replays from last checkpoint on recovery |
| Telemetry Consumer Service (ECS) | 1 | ECS task replacement + KCL rebalancing | Yes | Kinesis 24h retention ensures zero data loss; elevated latency during recovery is accepted |
| Valkey (ElastiCache) | 1 | Multi-AZ replica promoted to primary | Yes | SSE Streaming Service clients reconnect automatically |
| SSE Streaming Service (ECS) | 1 | ECS task replacement; NLB health checks | Yes | Browser falls back to DynamoDB polling within 5s |
| DynamoDB (7 tables) | 2 | Global Tables, continuous replication to us-west-2 | Yes | 99.999% availability SLA |
| Cognito | 2 | Daily export pipeline to us-west-2 | No, DR import is manual | Users must reset passwords in DR region. Note: Cognito import cannot begin until Terraform apply (~30 min) completes first, placing actual Cognito recovery closer to 45 min. This exceeds the Tier 2 RTO and is an accepted limitation. |
| Timestream for InfluxDB | 4 | Single-AZ instance; daily backup to S3 (RPO < 24h) | No, manual reprovision | Predictive maintenance only; S3 Parquet is system of record. Recoverable via backfill (ADR-012). |
| S3 (all buckets) | Supporting | 99.999999999% durability; CRR enabled for sensitive/operational buckets (dashcam, CloudTrail, Cognito exports, fleet reports, trip archives). CRR deferred for Parquet data lake and static web assets (ADR-010). | Yes | Near-zero RPO for CRR buckets; < 24h RPO for non-CRR buckets |

## 7.2 Backup and Recovery Strategy

### 7.2.1 DR Strategy Classification

| DR Characteristic | Implementation |
|---|---|
| Primary region resilience | Multi-AZ managed services (DynamoDB Global Tables, Kinesis, IoT Core, ElastiCache, Lambda, ECS) |
| Cross-region data replication | DynamoDB Global Tables: active, continuous replication to us-west-2. S3 CRR: enabled for sensitive/operational buckets (dashcam, CloudTrail, Cognito exports, fleet reports, trip archives). Deferred for Parquet data lake and static web assets (ADR-010). |
| Infrastructure recovery | Terraform apply to us-west-2 (~30 min) |
| Pilot Light elements | DynamoDB replica tables live in us-west-2; Terraform state stored remotely; KMS multi-region keys deployed |

### 7.2.2 Backup Strategy by Data Store

| Data Store | Backup Mechanism | RPO | Recovery Method |
|---|---|---|---|
| DynamoDB (7 tables) | Global Tables continuous replication + PITR (35-day window) | Near-zero (replication) / < 5 min (PITR) | Failover: use us-west-2 replica. Corruption: PITR restore. |
| S3 (data lake, dashcam, reports) | Versioning enabled; 99.999999999% durability. CRR to us-west-2 for dashcam, CloudTrail, Cognito exports, fleet reports, trip archives. | Near-zero (CRR buckets) / < 24 hours (Parquet data lake, static assets) | CRR buckets: failover reads from us-west-2 replica. Non-CRR buckets: object versioning for accidental deletion; data lake rebuildable from source (ADR-010). |
| Kinesis Data Streams | 24-hour stream retention | Near-zero (within retention) | Consumer replays from last checkpoint. |
| Cognito user pool | Daily automated export to S3 (see the Cognito DR pipeline below) | < 24 hours | Import to pre-provisioned DR user pool (~15 min). |
| Secrets Manager | Secure offline backup | < 24 hours (dependent on offline backup frequency) | Restore from offline backup during failover (~15 min). |
| Valkey (ElastiCache) | Ephemeral, stateless pub/sub broker | N/A | Recreated empty on recovery; Consumer resumes publishing to new channels. SSE clients fall back to DynamoDB polling until pub/sub resumes (ADR-007). |
| Timestream for InfluxDB | Daily `influx backup` to S3 (scheduled Lambda) | < 24 hours | Reprovision instance via Terraform; restore from S3 backup or backfill from S3 Parquet data lake. Predictive maintenance unavailable during recovery; core telemetry unaffected (ADR-012). |
| Terraform state | Remote S3 backend | Near-zero | Accessible from any region. |

### 7.2.3 Cognito Cross-Region DR Pipeline

Cognito lacks native cross-region replication. The platform fills this gap with an automated daily export pipeline that keeps a recoverable user pool snapshot in us-west-2. A Lambda function (invoked daily by EventBridge) exports the user pool to S3 CRR from us-east-1 to us-west-2. The only remaining impact of failing over to us-west-2 would be users needing to reset their passwords.

---

## 7.3 Failover Procedures

### 7.3.1 Intra-Region Failover

Intra-region failures are handled automatically by managed services and ECS. Multi-AZ deployments mean single-AZ outages don't need manual intervention. See the component mapping above for per-component recovery details.

### 7.3.2 Graceful Degradation

When individual components fail, the platform degrades instead of going fully offline. Recovery details are in the component mapping above.

- Valkey goes down: live dashboard updates pause briefly. Browser falls back to DynamoDB polling within 5s. All other pipelines keep running.
- SSE Streaming Service goes down: live dashboard updates stop. Browser falls back to DynamoDB polling within 5s. Data ingestion and persistence continue normally.
- Telemetry Consumer Service goes down: dashboard shows stale data. Kinesis buffers records (24h retention). Consumer recovers and replays from its checkpoint. No data loss.
- IoT Core goes down: vehicles cannot publish telemetry. Edge devices buffer locally. Data retransmits on reconnection.
- Single Lambda function fails: that specific feature is unavailable. Everything else keeps working. Failed invocations retry or go to DLQ.
- Firehose goes down: archival pauses. Real-time pipeline is unaffected. Firehose buffers internally and retries.
- Timestream for InfluxDB goes down: predictive maintenance alerts are unavailable. Core telemetry, persistence, and real-time dashboards are unaffected. Consumer circuit breaker opens and skips InfluxDB writes. S3 Parquet archival continues. Recoverable via backfill from S3 data lake (ADR-012).
- Athena / Location Services go down: analytics and enrichment are unavailable. Core telemetry and alerting are unaffected. Tier 4, tolerable delay.

### 7.3.3 Cross-Region Failover

The following is the cross-region failover procedure summary.

Trigger criteria: start cross-region failover only when multiple Tier 0/1 services are down for > 15 minutes and AWS Health Dashboard confirms regional degradation. For single-AZ or single-service outages, rely on intra-region auto-recovery mechanisms.

#### Critical Path Summary
1. Open incident ticket, notify stakeholders of service failure (~5min)

2. Apply Terraform infrastructure to us-west-2 (~30min)

3. Complete manual portion of failover plan (~15min):
    - Restore Secrets Manager values from offline backup
    - Invoke import-cognito function to restore to us-west-2
    - Deploy ECS service applications

4. DNS cutover: Update Route53 and CloudFront origins. Invalidate `/*` (~5min)

5. Validation and test workflows (~15min)

The plan should take around a maximum of 90min to complete. The decision to failover to a new region should be aborted if it's determined that the failover plan would likely exceed the us-east-1 recovery effort. 

#### 7.3.3a Route 53 Health Checks

Cross-region health checks provide automated failure detection for the failover decision:

| Health Check | Target | Alarm |
|---|---|---|
| API health | `GET /health` on API Gateway (us-east-1) | `RegionalHealthCheckFailed`: `HealthCheckStatus` < 1 for 5 minutes |
| Frontend health | `GET /` on CloudFront origin (us-east-1) | Combined with API health in calculated check |

Current health checks only monitor the API and frontend layers. A partial data-plane failure affecting only IoT Core ingestion would not trigger the alarm. Phase 2 enhancement: add IoT Core ingestion health check (synthetic MQTT publish with end-to-end validation).

---
[Capacity & Performance Planning](06-capacity-and-performance-planning.md) | [Next: Delivery & Implementation Plan](08-delivery-and-implementation-plan.md)