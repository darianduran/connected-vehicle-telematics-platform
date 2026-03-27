# ADR-003: Fargate Spot for Interruption-Tolerant SSE Workloads

## Context

The SSE Streaming Service is a stateless ECS Fargate service that pushes real-time vehicle data to user dashboards. It reconnects automatically after failure, making it a candidate for cost-optimized compute capacity.

## Decision

The SSE Streaming Service will use Fargate Spot capacity.

## Rationale

Fargate Spot provides 60-70% cost reduction. The trade-off is acceptable because the service is stateless, the browser handles automatic reconnection, DynamoDB polling provides a fallback within 5 seconds during interruption, and ECS automatically launches replacement Spot tasks.

## Rejected Alternatives

- **Standard Fargate:** Higher cost with no benefit for an interruption-tolerant workload.
- **EC2 Spot Instances:** Much more admin overhead.

## Reevaluation Triggers

- Sustained Spot unavailability exceeding SLA thresholds
- SSE Streaming Service becoming stateful
- Spot discount dropping below cost-benefit threshold

## Status

Accepted, 02 JAN 2026

## Consequences

- SSE compute cost reduced by ~60-70%.
- No front-end changes required.
- The DynamoDB polling fallback doubles as the Spot interruption safety net.
- ECS service `capacityProviderStrategy` changes to `FARGATE_SPOT`.
- CloudWatch alarms should monitor task replacement frequency to detect sustained Spot unavailability.
- Risk of degraded user experience during extended polling-only periods if Spot capacity is unavailable in the region.
- Operational monitoring required to detect elevated Spot interruption patterns.
