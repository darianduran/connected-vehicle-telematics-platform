# ADR-006: Kinesis Data Firehose for Archival and Reduced Stream Retention

## Context

The platform had no archive pipeline. A single Kinesis Data Stream with 7-day retention was the only recovery mechanism, and it provided no support for long-term historical analysis or auditing.

## Decision

Deploy Kinesis Firehose to archive telemetry to S3 and reduce Kinesis retention to 24 hours.

## Rationale

S3 is the clear archival target. Routing Kinesis directly to Firehose would inflate costs because Firehose bills in 5KB increments and most telemetry records are around 1KB. It would also expose raw VINs in the archive, violating ADR-005. Having the Telemetry Consumer Service batch and send records to Firehose solves both problems. I noticed the 5KB rounding issue during testing when the Firehose bill came in 5x higher than expected. Batching in the consumer brought it back in line.

Firehose handles batching, compression, and Parquet conversion natively, keeping the archive cost-effective and queryable via Athena.

## Rejected Alternatives

- **Kinesis to Firehose directly:** 5KB rounding inflates cost; bypasses pseudonymization.
- **IoT Core to Firehose directly:** Same rounding issue; same pseudonymization problem.
- **Consumer writes directly to S3:** Viable but requires replicating Firehose's batching and conversion. Revisit at scale.
- **Kinesis Data Analytics (Flink):** Overkill for archival.

## Reevaluation Triggers

- Real-time analytical workflows are needed (Firehose is not real-time).
- At larger scale, evaluate replacing Firehose with direct Consumer to S3 writes.

## Status

Accepted, 15 JAN 2026

## Consequences

- Kinesis retention reduced from 7 days to 24 hours, cutting stream costs.
- Telemetry archived to S3 in Parquet format, queryable via Athena.
- Eliminates the need to store time-series data in DynamoDB (see ADR-009).
- Consumer crash recovery window is reduced to 24 hours.
- Firehose introduces archival latency. It is not a real-time delivery path.
