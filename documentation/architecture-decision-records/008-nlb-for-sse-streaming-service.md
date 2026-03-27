# ADR-008: Retain NLB for SSE Streaming Service

## Context

After the `telemetry-server` was replaced by IoT Core for telemetry ingestion (see ADR-004), the NLB serves only a single listener to the SSE Streaming Service. This ADR evaluates whether to retain the NLB or migrate to another service to cut costs.

## Decision

The NLB will be retained for the SSE Streaming Service.

## Rationale

The NLB provides the simplest and most reliable solution for long-lived SSE connections. API Gateway options introduce timeout constraints, payload limits, and added latency (~100ms per update) incompatible with long-lived SSE connections, plus additional reconnection management logic on the frontend.

## Rejected Alternatives

- **API Gateway HTTP API:** 30-second idle timeout kills connections during data gaps and 10MB payload limit per connection lifetime forces frequent disconnect / reconnects. These constraints could be worked around with frontend modifications but would require additional development overhead.
- **API Gateway REST API (streaming mode) + ALB:** Requires a pricier load balancer with added latency and complexity to manage 15-minute disconnections.
- **ALB:** More expensive than NLB with no meaningful benefits for this use case.

## Reevaluation Triggers

- SSE Streaming Service retired in favor of WebSocket delivery
- API Gateway removing the 30-second timeout constraint
- Additional services added that would benefit from a shared ALB

## Status

Accepted, 25 JAN 2026

## Consequences

- NLB retains only the port 3000 listener for SSE.
- No frontend changes required.
- NLB cost remains unchanged from the pre-evaluation architecture.
- NLB provides no application-layer features (no WAF integration, no path-based routing, no request inspection).
- Single-listener NLB limits future flexibility if additional HTTP services need load balancing behind the same resource.
