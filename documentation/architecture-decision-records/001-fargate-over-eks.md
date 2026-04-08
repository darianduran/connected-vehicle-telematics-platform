# ADR-001: ECS Fargate over EKS

## Context

The platform originally ran three containerized services on EKS and ECS. The EKS container app was a vendor-specific Telemetry Server (vehicle telemetry ingestion) that was natively designed for K8s. For ECS, the two services are the Telemetry Consumer Service (stream processing), and the SSE Streaming Service (real-time dashboard delivery). Minimizing admin overhead and infrastructure cost are clear objectives of this solution.

## Decision

ECS Fargate will be used for all containerized workloads.

## Rationale

EKS has a monthly control plane charge before any node costs. Fargate eliminates EC2 instance management entirely. For only two services with straightforward networking, Kubernetes abstractions add significant costs without proportional value.

## Rejected Alternatives

- **EKS with Fargate:** Monthly control plane charge and complex IAM setup.
- **EKS with managed node groups:** Control plane charge + EC2 costs with significant admin overhead.
- **ECS on EC2:** Requires EC2 instance management.

## Reevaluation Triggers

I would re-evaluate this if the service would grow substantially or compatibility with other cloud service providers was needed.

## Status

Accepted, 29 DEC 2025

## Consequences

- Avoids the EKS control plane charge.
- Service-to-service discovery relies on AWS Cloud Map rather than Kubernetes-native DNS, adding an AWS-specific dependency.
- ECS is AWS-proprietary, reducing portability compared to Kubernetes.
- Future services requiring Kubernetes-native features would require re-evaluation.
