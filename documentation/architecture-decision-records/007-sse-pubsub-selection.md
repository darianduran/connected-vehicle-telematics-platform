# ADR-007: SSE Pub/Sub Broker Selection

## Context

The SSE Streaming Service provides live updates from the backend to client dashboards. To scale to concurrent clients, a Pub/Sub broker streams data to the SSE Streaming Service. The original implementation used ElastiCache Redis. We evaluated Redis, IoT Core, and ElastiCache Valkey as alternatives.

## Decision

ElastiCache **Valkey** chosen as the Pub/Sub broker for the SSE Streaming Service.

## Rationale

All three services are viable Pub/Sub broker options, but Valkey provides the best performance at the lowest cost.

IoT Core's per-message pricing (metered to 5KB) scales poorly for this platform's wide-scope, constantly-updated data. Valkey is cheaper at every fleet size. At 1K vehicles IoT Core would cost roughly $90/mo for pub/sub alone, while Valkey is under $15/mo. The gap widens as the fleet grows.

Valkey charges an hourly rate per node regardless of message volume, making costs predictable.

Beyond cost, Valkey outperforms Redis. Benchmark data shows ~37% better write throughput and ~60% lower latency on GET operations. Since the original implementation used Redis, migrating to Valkey is a drop-in replacement using the same `PUBLISH` and `SUBSCRIBE` APIs.

## Rejected Alternatives

- **Redis Pub/Sub:** Functionally equivalent to Valkey but at higher cost and marginally lower performance.
- **IoT Core MQTT for internal pub/sub (v1):** Cost-prohibitive at any meaningful fleet size.
- **ElastiCache Serverless for Valkey:** Viable, but node-based pricing is more predictable for a steady-state stream.
- **Self-managed Valkey on ECS/EC2:** Significant admin overhead for no meaningful cost difference.
- **Replace SSE Streaming Service with IoT Core WebSocket:** High per-message costs and larger frontend changes required.

## Reevaluation Triggers

- ElastiCache Serverless pricing becoming competitive with node-based pricing for steady-state workloads
- Platform scaling beyond node-based pricing efficiency
- AWS deprecating or changing the Valkey offering

## Status

Accepted, 20 JAN 2026

## Consequences

- Telemetry Consumer Service publishes data to Valkey Pub/Sub channels.
- SSE Streaming Service subscribes to Valkey channels for connected clients.
- SSE Streaming Service implementation remains unchanged.
- DynamoDB polling fallback during SSE interruption is unchanged.
- Reverting from Valkey to IoT Core would require more admin overhead since IoT Core is a fully managed service; reverting to Redis is trivial due to API compatibility.
