# ADR-010: Single-Region Compute with DynamoDB Cross-Region DR

## Context

The platform needed a deployment strategy balancing cost, complexity, and DR posture. DynamoDB operational state was the critical failover bottleneck. A PITR restore of 7 tables would take 1-2 hours, dominating any recovery timeline.

## Decision

Single region (us-east-1) deployment will be used for compute services only. All DynamoDB tables will be replicated to us-west-2 via Global Tables. S3 CRR will be deferred for the time being.

## Rationale

Configuring DynamoDB as Global Tables eliminate the long PITR restoration times and raise DynamoDB SLA to 99.999%. At larger scale, Global Tables will roughly double the DynamoDB bill adding ~300/mo. S3 CRR is deferred because S3 data is not needed during failover and is already durable. A hot or warm multi-region deployment for compute services is disproportionate to the current scale. The several hundred dollar cost per month is not worth the manual failover trade off. 

## Rejected Alternatives

- **Single-region without Global Tables:** 2-4 hour RTO, PITR restore is the dominant bottleneck.
- **Full active-passive:** Adds several hundred dollars/mo for S3 CRR and standby compute protecting already eleven-9s-durable data.
- **Full active-active:** Requires dual IoT Core, regional Kinesis, Valkey Global Datastore, and app-level conflict resolution. Disproportionate to current scale.

## Consequences

- RTO reduced from 2-4 hrs to ~45 min to 1.5 hrs. RPO near-zero for DynamoDB.
- S3 remains single-region until CRR can be justified.

## Status

Accepted (18 FEB 2026), supersedes previous single-region-only decision (15 FEB 2026)

## Reevaluation Triggers

- 1 hour or less RTO requirements are needed
- us-east-1 regional outage exposing unacceptable risk
