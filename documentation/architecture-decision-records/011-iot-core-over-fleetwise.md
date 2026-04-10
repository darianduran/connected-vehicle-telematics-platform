# ADR-011: Retaining IoT Core over IoT FleetWise for Telemetry Ingestion

## Context

A comparison was conducted between AWS IoT FleetWise and the current IoT Core (Basic Ingest) implementation for vehicle telemetry ingestion. A hybrid architecture was also evaluated.

## Decision

FleetWise is not suitable for the platform. IoT Core remains the sole ingestion service.

## Rationale

The per-vehicle cost is $0.60 per vehicle a month exceeds the entire IoT Core bill at any fleet size. At peak scale, Fleetwise would cost ~$3,000/mo alone. The hybrid design below also costs more than the current archive and Athena pipeline. Fleetwise also does not support native Kinesis support, its MQTT bridge introduces messaging charges which IoT Core is able to avoid using Basic Ingest. Live dashboard functionality is not possible with Fleetwise as it adds high latency with S3 buffering. Lastly, Fleetwise is not supported in us-west-2 which is a conflict in the disaster recovery plan.

## Rejected Alternatives

- **FleetWise full replacement:** 14-17x cost increase with real-time pipeline incompatibility.
- **Hybrid (IoT Core + FleetWise):** This alternative explored sending filtered data consisting of append-only data that Athena processes. This hybrid approach still exceeds the costs of Firehose and Athena combined.

## Reevaluation Triggers

- The platform wants a managed solution to handle decoding different auto manufacturer CAN data
- Region parity aligns with the disaster recovery plan
- AWS adds Kinesis as a native FleetWise campaign destination
- FleetWise pricing model changes 

## Status

Accepted, 05 MAR 2026

## Consequences

- IoT Core Basic Ingest remains the sole ingestion path.
- Edge device software unchanged.
- Breadcrumb filtering remains the Telemetry Consumer Service's responsibility.
