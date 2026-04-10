# ADR-012: InfluxDB for Predictive Maintenance Analytics

## Context

The platform archives all telemetry to S3 via Firehose in Parquet format (ADR-006, ADR-009). Athena provides ad-hoc queries over this data lake but lacks native time-series functions needed for predictive maintenance: trend analysis, anomaly detection, and interpolation. These are possible in Athena SQL but are complex and impractical for near-real-time alerting loops.

## Decision

Timestream for InfluxDB will be used for predictive maintenance analysis.

## Rationale

Only 9 data types with genuine predictive value are routed to InfluxDB (~15-20% of total volume): battery telemetry, charging sessions, drivetrain metrics, tire pressure, steering health, thermal management, suspension health, fluid levels, and vehicle maintenance. I initially routed everything to InfluxDB and storage costs climbed fast. Filtering down to these types cut write volume by ~80% with no loss in analytical capability.

InfluxDB provides native `derivative()`, `movingAverage()`, and `monitor.check()` functions with sub-second query latency on recent data. Athena has no native interpolation and 5-30s cold-start latency per query, making it impractical for alerting. Athena remains the right tool for ad-hoc historical queries over the full data lake.

The Telemetry Consumer Service already fans out to DynamoDB, Valkey, and Firehose by event type. InfluxDB is a fourth selective target using the same pattern.

## Rejected Alternatives

- **Route all telemetry to InfluxDB:** 5-7x storage cost increase with no analytical benefit for non-time-series data.
- **Athena-only:** Cold-start latency impractical for near-real-time alerting.
- **Apache Flink on Kinesis Analytics:** Overkill for hourly batch analytics.
- **SageMaker:** Premature. Rule-based Flux queries cover current requirements.

## Consequences

- Telemetry Consumer Service gains a fourth write target with selective routing.
- Single db.influx.medium instance, Single-AZ. Acceptable deviation from ADR-010's multi-AZ standard since S3 Parquet is the system of record and predictive maintenance is a Tier 4 capability.
- RPO is 24 hours via daily backup to S3. Recoverable via S3 Parquet backfill.
- Cost is ~$90-95/mo fixed regardless of fleet size.

## Status

Accepted 13 MAR 2026

**Reevaluation triggers:**
- Write throughput exceeds db.influx.medium capacity (sustained >80% CPU)
- HA required for predictive maintenance
- ML-based predictions needed beyond rule-based thresholds
- InfluxDB 3 SQL-based alternative proves sufficient
