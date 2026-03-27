# 9.0 Operations and Support

## 9.1 Monitoring Setup

### 9.1.1 Observability Approach

| CloudWatch Tool | Role |
|---|---|
| CloudWatch Metrics | Infrastructure and application metrics with alarms |
| CloudWatch Logs / Logs Insights | Centralized structured logging with ad-hoc query capability |

**Signal coverage:**
| Signal | Sources |
|---|---|
| Latency | API Gateway latency, Lambda duration, DynamoDB `SuccessfulRequestLatency`, InfluxDB query duration |
| Errors | API Gateway `4XXError`/`5XXError`, Lambda errors, DynamoDB `SystemErrors`, IoT Core rule action failures, KCL exceptions |
| Throughput | API Gateway request count, Kinesis `IncomingRecords`, IoT Core `RulesExecuted`, DynamoDB consumed capacity |
| Saturation | Kinesis `WriteProvisionedThroughputExceeded`, DynamoDB `ThrottledRequests`, Lambda concurrent executions, ECS CPU/memory utilization, Valkey `EngineCPUUtilization` and `DatabaseMemoryUsagePercentage` |

### 9.1.2 Key Metrics by Signal

| Service | Latency | Error Rate | Throughput | Saturation |
|---|---|---|---|---|
| API Gateway | `Latency` | `5XXError`, `4XXError` | `Count` | Throttle count |
| Lambda (all functions) | `Duration` | `Errors`, `Throttles` | `Invocations` | `ConcurrentExecutions` vs. reserved concurrency |
| IoT Core | `RuleMessageThrottled` | `RulesExecuted` failures, `TopicMatch` errors | `RulesExecuted` | `RuleMessageThrottled` |
| Kinesis | `GetRecords.Latency` | `ReadProvisionedThroughputExceeded` | `IncomingRecords`, `IncomingBytes` | `WriteProvisionedThroughputExceeded`, `IteratorAgeMilliseconds` |
| DynamoDB | `SuccessfulRequestLatency` | `SystemErrors` | Consumed RCU/WCU | `ThrottledRequests`, `AccountProvisionedReadCapacityUtilization` |
| ElastiCache Valkey | `StringBasedCmdsLatency` | `CacheErrors` | `CurrConnections`, `Evictions` | `EngineCPUUtilization`, `DatabaseMemoryUsagePercentage` |
| InfluxDB | Custom: query latency, write latency | Custom: write failures (circuit breaker state) | Custom: points written/sec | Disk utilization, memory utilization |

### 9.1.3 Dashboards

Three CloudWatch dashboards serve different stakeholders:

- **Operations Dashboard (support)**
  - Kinesis `IteratorAgeMilliseconds` and consumer lag
  - DynamoDB throttle counts and latency by table
  - Lambda error rates and duration by function
  - ECS task health (running count, CPU, memory)
  - Valkey connection count and memory utilization
  - Active alarm summary widget

- **API & User Experience Dashboard (engineering)**
  - API Gateway latency and error rates by endpoint
  - SSE active connection count and reconnect rate
  - OEM Command Proxy success rate and duration
  - Token Generator request volume and error rate
  - IoT Core message throughput and rule failures

- **Executive Dashboard (leadership)**
  - User-wide vehicle connectivity rate
  - Telemetry ingestion volume
  - API request availability
  - Cost trend (daily spend vs. budget)

### 9.1.4 Log Retention

| Source | Destination | Retention |
|---|---|---|
| ECS services and Lambda functions | CloudWatch Logs | 14 days |
| API Gateway access logs | CloudWatch Logs | 14 days |
| VPC Flow Logs | CloudWatch Logs | 90 days |
| CloudTrail | S3 + CloudWatch Logs | 365 days |
| S3 access logs | S3 (logs bucket) | 90 days |

---
[Delivery & Implementation Plan](08-delivery-and-implementation-plan.md) | [Next: Cost Breakdown](10-cost-breakdown.md)