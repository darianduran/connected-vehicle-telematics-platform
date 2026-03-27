# ADR-002: Kinesis Data Streams over Amazon MSK

## Context

The platform requires a durable, real-time streaming layer to ingest vehicle telemetry and deliver it to the Telemetry Consumer Service (the ECS Fargate service that processes incoming telemetry from the stream). The stream must handle sustained throughput of thousands of events per second with data redundancy for replays.

## Decision

Use Kinesis Data Streams (on-demand mode) as the ingestion stream.

## Rationale

Kinesis on-demand eliminates shard management during early phases. Capacity scales automatically without admin overhead. The platform has a single consumer target with native AWS integrations connecting Kinesis to ECS Fargate, making Kinesis the ideal fit.

MSK is stronger for complex multi-consumer topologies. With a single consumer, MSK capabilities are unnecessary. Transitioning to either MSK Serverless or MSK Provisioned would require VPC network and IAM modifications plus consumer service changes.

## Rejected Alternatives

- **MSK Serverless:** Higher cost with additional complex initial setup for a single-consumer use case.
- **MSK Provisioned:** Higher cost with additional complex setup and capacity planning overhead.
- **SQS as primary ingestion:** SQS is more suitable as a job buffer between Consumer and Lambda Functions.

## Reevaluation Triggers

- Additional consumers that pull from the data stream are provisioned
- Event routing directly from the data stream rather than the Telemetry Consumer Service triggering events
- Cloud portability requirements increase

## Status

Accepted, 30 DEC 2025

## Consequences

- On-demand mode handles all shard management automatically during early phases.
- Automatic scaling without capacity planning reduces operational overhead.
- Native AWS integration reduces development effort compared to MSK alternatives.
- Lower cost than all MSK options at current scale.
- All event types (vehicle data and internal debug data) share a single stream.
- Single point of failure risk exists, but failover is as easy as updating a SSM parameter for the Consumer.
- Vendor lock-in to Kinesis is an acceptable early-stage trade-off but needs reevaluation if portability requirements change.
