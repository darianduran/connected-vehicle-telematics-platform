# ADR-004: IoT Core Replacing ECS Fargate Telemetry Server

## Context

The platform previously ingested vehicle telemetry through a vendor-provided telemetry server on ECS Fargate. This locked the platform into a single auto manufacturer, incurred vendor-specific fees, and required running the server 24/7. When I tried to add a second manufacturer, it was immediately clear the architecture was a dead end. The vendor server only spoke one protocol with no plans to support others. IoT Core with a generic CAN bus decoder on the edge device made the platform manufacturer-agnostic overnight.

## Decision

IoT Core will replace the former `telemetry-server` service.

## Rationale

IoT Core is built for high-volume telemetry transport from IoT devices to AWS. It provides device onboarding, per-device mTLS, and native Kinesis integration, eliminating the compute and code overhead of a self-managed server. Any vehicle with a CAN bus interface is now compatible with the platform.

IoT Core costs more than the Fargate server (~$260/mo at 5K vehicles vs ~$60/mo), but that increase is the cost of manufacturer-agnostic ingestion. Basic Ingest is configured to eliminate per-message charges.

## Rejected Alternatives

- **Custom built application (ECS/EC2/EKS):** Replicates IoT Core functionality with significant development and admin overhead.
- **IoT FleetWise:** Cost-prohibitive and incompatible with the real-time pipeline. See ADR-011.

## Reevaluation Triggers

- Cost differential changes materially at larger scale
- Platform needs to support protocols beyond MQTT
- Multi-cloud portability becomes a requirement

## Status

Accepted, 05 JAN 2026

## Consequences

- The `telemetry-server` service and its dependencies are eliminated.
- The NLB only serves the SSE Streaming Service now.
- The Telemetry Consumer Service remains unchanged.
- IoT Core handles device authentication and mTLS workflows.
- Edge devices publish to `$aws/rules/{rule-name}` (Basic Ingest) instead of standard MQTT topics.
