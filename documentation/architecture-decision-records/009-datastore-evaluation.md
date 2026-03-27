# ADR-009: DynamoDB Table Consolidation and Time-Series Migration to S3

## Context

The platform had 21 DynamoDB tables, each with its own CloudWatch alarms, capacity config, backup policies, and IAM permissions. Time-series data was also stored in DynamoDB despite high write volume and low read frequency. The 21-table design grew organically as each new feature got its own table. Once I mapped out the access patterns, it was obvious most tables shared the same partition key and could be merged with no performance impact.

## Decision

Consolidate 21 DynamoDB tables to 7 and migrate append-only time-series data to S3.

## Rationale

Tables sharing the same partition key can be merged with zero performance impact. Consolidation from 21 to 7 tables cuts operational surface proportionally. Time-series data in S3 with lifecycle policies is ~90% cheaper than DynamoDB for these access patterns and enables Athena queries for long-term trend analysis.

**7-table consolidation:**
- **Vehicle-scoped (2):** `vehicle-live` and `trip-history`. Merged from 5 tables.
- **Organization-scoped (2):** `organization` and `fleet-operations`. Merged from 9 tables.
- **Internal/admin (3):** `vin-mapping`, `command-audit`, `oem-tokens`. Each isolated due to unique access patterns or security requirements (see ADR-005).

**Time-series data migrated to S3 Parquet via Firehose (see ADR-006):** breadcrumbs, telemetry events, alerts, charging sessions, security events.

## Rejected Alternatives

- **Keep 21 tables:** Excessive operational overhead; DynamoDB misused for time-series data.
- **Single table:** Hot partition risks between vehicle and organization data; weakens IAM scoping.
- **Everything to S3:** Vehicle current-state requires single-digit ms reads for SSE and API. S3 cannot meet this.

## Consequences

- DynamoDB write volume drops substantially. At 5K vehicles, datastore costs drop from ~$900/mo to ~$350/mo (before Global Tables replication per ADR-010).
- Historical read paths shift from DynamoDB point queries to Athena, introducing higher latency for those access patterns.
- S3 lifecycle policies required per data type.

## Status

Accepted 05 FEB 2026

**Reevaluation triggers:**
- At larger scale, evaluate writing directly to S3 from the consumer if Firehose costs become significant.
- New access patterns requiring low-latency reads on archived data
