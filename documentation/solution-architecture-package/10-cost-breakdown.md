# 10.0 Cost Breakdown

> Note: 
> 
> All pricing reflects us-east-1 pricing as of February 2026
> 
>  Costs are approximate and modeled at three fleet sizes to show how costs scale 

## 10.1 Fleet Size Assumptions

The solution was designed to support a theoretical maximum limit of 10,000 vehicles, but cost models focus on realistic short-term fleet sizes. The three phases of the cost model are 100, 1000, and 5000 vehicles. 

| Parameter | Pilot (100) | Growth (1K) | Scale (5K) |
|---|---|---|---|
| Connected vehicles | 100 | 1,000 | 5,000 |
| Peak events/sec (fleet-wide) | ~50 | ~500 | ~2,500 |
| Event payload size | ~1 KB | ~1 KB | ~1 KB |
| Avg events/vehicle/day | ~5,600 | ~5,600 | ~5,600 |
| Monthly messages (fleet) | ~17M | ~169M | ~845M |
| Monthly data volume (fleet) | ~17 GB | ~169 GB | ~845 GB |
| Dashboard MAUs | 20 | 200 | 800 |
| API requests/day | ~10K | ~100K | ~400K |
| Dashcam uploads/day | 5 clips (~50 MB each) | 50 clips | 200 clips |

## 10.2 Detailed Production Cost Breakdown

### 10.2.1 DynamoDB
> **DynamoDB on-demand pricing**:
> - $0.625/million WRUs
> - $0.125/million RRUs 
> - $0.25/GB of storage per month
> - $0.09/GB of cross-region data transfer per month
> - $0.20/GB of PITR per month

| Fleet Size | Approx. Monthly Cost | Notes |
|---|---|---|
| 100 | ~$20 | Minimal writes, storage negligible |
| 1K | ~$120 | Global Tables replication starts to matter |
| 5K | ~$575 | Write volume is the dominant cost |


There is a total of 7 DynamoDB tables in the solution since *ADR-009* took effect. All the tables are configured as Global Tables, as a result, write operations are billed twice. 

At around 5k vehicles, Global Tables replication roughly doubles the DynamoDB bill compared to single region. Global tables are a non-negotiable configuration as it stores critical application data. On-demand mode is pricier but reduces admin overhead in early stages of the solution. AWS suggests provisioned capacity mode for predictable workloads since it's 15-25% cheaper than on-demand, however transitioning only makes sense once baselines are established.

### 10.2.2 IoT Core

> **IoT Core pricing:**
> - $1.00/million messages
> - $0.00/million basic ingest messages
> - $0.08/million connected minutes
> - $0.15/million rules triggered
> - $0.15/million actions executed


Since *ADR-004*, IoT Core has been the core ingestion service. At 5k vehicles, IoT Core estimated usage is as follows:
- ~845M messages (Basic Ingest)
- ~115M connectivity minutes
- ~845M rules triggered
- ~845M actions executed

IoT Core has been configured to optimize costs as much as possible. Basic Ingest is configured to eliminate messaging charges. Connectivity charges are relatively negligible at any scale and cost less than $10. Rules and actions are the main cost-drivers both around $125 each.

| Fleet Size | Approx. Monthly Cost |
|---|---|
| 100 | ~$5 |
| 1K | ~$55 |
| 5K | ~$265 |


### 10.2.3 Kinesis Data Streams

> **Kinesis Data Stream (on-demand):**
> - $0.04/stream-hours 
> - $0.080/GB ingested
> - ~~$0.10/GB ingested (extended retention)~~
> - $0.040/GB retrieved


Kinesis Data Stream is deployed in on-demand mode during early stages of the platform. Like DynamoDB, provisioned capacity is cheaper long-term but requires accurate baselines to be established to transition to it. Additional concerns of provisioned mode are outlined in section 6.3 of the *Capacity and Performance Planning* document.

The stream hour charge is essentially fixed at $30/mo since the data stream is active 24/7. The retention window has been reduced to just 24hrs per *ADR-006*.

| Fleet Size | Monthly Ingest | Approx. Monthly Cost |
|---|---|---|
| 100 | ~17 GB | ~$30 |
| 1K | ~169 GB | ~$50 |
| 5K | ~845 GB | ~$130 |

### 10.2.4 Networking

> **Networking pricing:**
> - NAT Gateway: $0.045/hr + $0.045/GB processed
> - Network Load Balancer (NLB): $0.0225/hr
> - Interface Endpoints: $0.01/hr + $0.0004/GB processed
> - S3/DynamoDB Gateway Endpoints: $0.00

Networking cost remains relatively fixed even at different stages of growth:
- NAT Gateway (2x multi-AZ): ~$70 
- NLB (SSE traffic only): ~$20 
- Kinesis + Firehose Interface Endpoints (2 AZs each): ~$30 

In early stages, networking costs are very disproportionate relative to the other services, but barely increase at larger scale.

| Fleet Size | Approx. Networking Total |
|---|---|
| 100 | ~$125 |
| 1K | ~$130 |
| 5K | ~$135 |

### 10.2.5 Compute (Fargate)

> **Elastic Container Service (ECS) pricing:**
> - $0.04048/vCPU per hour of operation
> - $0.004445/GB data processed
> - Spot Capacity: Up to 70% discount
> 
Since *ADR-004*, the Telemetry Consumer Service and SSE Streaming Service are the only two Fargate applications. SSE Streaming Service is configured in spot capacity mode to optimize costs further, see *ADR-003* for more info. 

In early stages, only one task per service will run, as the platform scales the Consumer will increase to 3 tasks. Configurations may vary at different stages but will generally be:
- Telemetry Consumer Service - 1vCPU / 2GB memory / Fargate Capacity = ~$35 per task
- SSE Streaming Service - 0.25vCPU / 0.5 GB memory / Spot Capacity = ~$5 per task



| Fleet Size | Est. Tasks | Est. Fargate Cost |
|---|---|---|
| 100 | 2 tasks (1 Consumer, 1 SSE) | ~$40 |
| 1K | 3 tasks (2 Consumer, 1 SSE) | ~$75 |
| 5K | 4 tasks (3 Consumer, 1 SSE) | ~$110 |

### 10.2.6 Timestream InfluxDB

>**Timestream InfluxDB pricing:**
> - db.influx.medium (1 vCPU / 8GB RAM) $0.12/hr

InfluxDB utilizes a single-AZ provisioned db.influx.medium instance. Costs are essentially fixed at any scale since the instance runs 24/7. The total across stages will be around $90 per month.

### 10.2.7 Kinesis Firehose

> **Firehose pricing:**
> - $0.029/GB ingested
> - Billed in 5KB increments


Firehose pricing is relatively cheap in this solution since the Consumer was designed to compile records into 5KB batches.

| Fleet Size | Approx. Monthly Cost | 
|---|---|
| 100 | ~$5 | 
| 1K | ~$10 | 
| 5K | ~$40 |


### 10.2.8 Small and Fixed Costs

These services cost under $25/mo each at all fleet sizes. Grouped here to keep the breakdown focused.

**Lambda:** 12 total functions are used and costs ~$5/mo at 100 vehicles and ~$25/mo at 5K vehicles.

**ElastiCache** (cache.t4g.micro): At early stages, ElastiCache will be a single-node costing ~$10/mo and raise to $20/mo with a multi-AZ deployment at 5k vehicles. ElastiCache has been transitioned from Redis to Valkey to save up to 20% monthly, see *ADR-007* for more info.

**API Gateway** (REST API): Less than $5 at pilot and ~$40 at 5k vehicles.

**Cognito:** Remains in the free tier at every stage.

**Observability** (CloudWatch, CloudTrail, GuardDuty): ~$30/mo at pilot and ~$40/mo at 5K vehicles. Bulk of costs are from dashboards, alarms, and metrics but remain relatively fixed. 

**WAF**: Fixed base costs are about $10/mo with request processing ~$15/mo at pilot and ~$25 at 5k vehicles. 

**S3 (non-telemetry archive)**: Since *ADR-010* has been in effect, CRR has added to monthly costs of the S3 buckets but are mostly negligible. At pilot, costs will be below $5/mo and 5k vehicles will be about $15/mo.

**SQS/SNS**: About $5/mo at 5k vehicles, negligible at any stage below.

**Security** (KMS + Secrets Manager): ~$10 fixed costs at all stages.

**CloudFront**: Under $5/mo at all stages.

**Other** (Athena, S3 (Telemetry Archive), ECR, Cloud Map, EventBridge, Route 53, Location Service): ~$15/mo combined.

## 10.3 Monthly Cost Summary

| Service Category | 100 Vehicles | 1K Vehicles | 5K Vehicles |
|---|---|---|---|
| DynamoDB Global Tables | ~$20 | ~$120 | ~$575 |
| IoT Core | ~$5 | ~$55 | ~$265 |
| Kinesis Data Streams | ~$30 | ~$50 | ~$130 |
| Networking | ~$125 | ~$130 | ~$135 |
| InfluxDB | ~$90 | ~$90 | ~$90 |
| ECS Fargate | ~$40 | ~$75 | ~$110 |
| Kinesis Firehose | ~$5 | ~$10 | ~$40 |
| Lambda + API Gateway | ~$5 | ~$25 | ~$65 |
| Observability + Security | ~$35 | ~$35 | ~$45 |
| Other (Valkey, WAF, S3, SQS/SNS, CloudFront, misc) | ~$35 | ~$45 | ~$75 |
| **Total** | **~$400** | **~$600** | **~$1,500** |
| **Per vehicle/month** | **under $4** | **under $0.60** | **under $0.30** |


## 10.4 Future Cost Optimizations

At launch, operational simplicity takes priority over aggressive cost optimization. On-demand pricing is used at every applicable service to provide zero config scaling. As traffic patterns stabilize and become understood, these optimizations become worth evaluating.

If I were optimizing today, I'd start with DynamoDB provisioned capacity and Kinesis provisioned mode. Those two alone would save $100-150/mo at 1K vehicles with minimal operational risk. Savings Plans are worth it once you're confident the architecture is stable, but locking in a 1-year commitment before traffic patterns are established is premature.

- DynamoDB provisioned capacity: Could cut down on the largest cost-driver of the solution.
- Compute Savings Plans (1yr, no upfront costs): can save around 30% for Fargate and Lambda.
- Database Savings Plans: cut rates from $0.12 to $0.096 for Timestream InfluxDB db.influx.medium
- Kinesis provisioned mode: A single provisioned shard costs around $10/mo compared to on-demand $35-50/mo but requires shard management.
- CloudFront Security Savings Bundle: 1yr commitment covering CloudFront + WAF at up to 30% discount.

These are worth revisiting once the fleet is past 1K vehicles and traffic patterns are predictable.

## 10.5 Environment Cost Comparison

The dev environment runs about $250/mo. Main savings come from single-region DynamoDB (no Global Tables), one NAT gateway, Spot for all Fargate tasks, and provisioned Kinesis with one shard. The InfluxDB instance is the same cost in both environments since it is a fixed instance. Dev uses 7-day bucket retention to minimize storage.

---
[Operations & Support](09-operations-and-support.md)