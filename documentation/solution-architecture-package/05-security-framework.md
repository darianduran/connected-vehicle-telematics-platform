# 5.0 Security Framework

## 5.1 Data Protection
### 5.1.1 Data Classification

| Tier | Description |
|---|---|
| **Restricted** | Data certain to cause severe harm to customers, the organization, and vehicles if disclosed or altered without authorization. |
| **Confidential** | Operational or user data that could cause moderate privacy and security risk if exposed. |
| **Internal** | Relatively low risk if disclosed but not intended for public access. Exposure would not directly compromise user privacy or vehicle security. |

#### Data Classification Assignments

| Asset | Classification |
|---|---|
| OEM tokens | Restricted |
| VIN (PII) | Restricted |
| Secrets (API keys, credentials) | Restricted |
| Fleet reports | Restricted |
| Dashcam footage (PII) | Restricted |
| Vehicle state / telemetry data | Confidential |
| Historic trip data | Confidential |
| Command audit logs | Confidential |
| CloudWatch application logs and metrics | Internal |

Other operational data such as maintenance records and security events fall under the Confidential classification.

### 5.1.2 VIN Pseudonymization

The Telemetry Consumer Service handles pseudonymization of the VIN data before being written or processed downstream. The Consumer Service retrieves the HMAC-SHA256 key from Secrets Manager. Raw VINs never reach data stores or applications beyond the Consumer. The sole exception is the `vin-mapping` DynamoDB table which allows internal admins to map VIN to pseudoVIN. Access to this table is heavily restricted to specific IAM admin roles with read only access. Every API action against the table is fully audited by CloudTrail and sets of alerts using SNS.


### 5.1.3 Data Retention Requirements

Retention periods are based off classification and audit requirements:

| Data Asset | Retention Period | Destruction Requirement |
|---|---|---|
| Telemetry Parquet data lake | 1 year active, archival thereafter | Lifecycle-managed deletion after archival period |
| Security events | 2 years active, archival thereafter | Lifecycle-managed deletion after archival period |
| Dashcam compressed footage | 90 days active, archival to 180 days | Lifecycle-managed deletion after archival period |
| CloudTrail logs | 365 days immutable (Object Lock, Compliance mode) | Cannot be deleted during retention; lifecycle-managed after |
| Command audit records | 90 days | Automatically expired via DynamoDB TTL |

## 5.2 Network Security

### 5.2.1 VPC Endpoint Policies

The S3 and DynamoDB gateway endpoints use least privilege policies that are scoped to platform resources only. The idea is to limit the access at the VPC level to prevent data exfiltration to private/internal or cross account data stores.

| Endpoint | Scope | Permission Restrictions |
|---|---|---|
| S3 Gateway | Platform buckets only (telemetry, dashcam, trip-archive, report, cloudtrail-log, frontend, cognito-export) | `GetObject`, `PutObject`, `ListBucket`, `GetBucketLocation` |
| DynamoDB Gateway (Operational Tables) | Platform tables only (`vehicle-live`, `trip-history`, `organization`, `fleet-operations`, `command-audit`, `oem-tokens`) | Full CRUD operations (`GetItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `Query`, `Scan`, batch operations) |
| DynamoDB Gateway (`vin-mapping`) | Isolated statement for `vin-mapping` only | Selective read-only access: `GetItem` and `Query` |

### 5.2.2 WAF

AWS WAF is attached to CloudFront with these protections:

- AWS Managed Rulesets for common exploits (OWASP Top 10)
- Rate limiting: 500 requests per IP per 5 minutes
- Geo-restriction: North America only

### 5.2.3 NLB Compensating Controls

The SSE Streaming Service path essentially bypasses the WAF by routing through the NLB. Controls are put in place to compensate:

- Cognito JWT validation: SSE connections require a valid Cognito token verified on connection establishment, otherwise requests are rejected
- Vehicle ownership verification: SSE Streaming Service checks vehicle ownership by cross referencing the `pseudoVIN` from the requester's JWT claim set to the requested vehicle `pseudoVIN`
- Idle connection termination: Connections automatically terminate after a configurable idle timeout passes
- Network-layer access restriction: Security group restricts inbound traffic to the SSE port from the NLB only.

### 5.2.4 Device and Service Authentication

| Authentication Path | Control | Notes |
|---|---|---|
| Vehicle to AWS | IoT Core Device Certificates | The Edge Device and IoT Core must mutually authenticate (mTLS) |
| User to API | Cognito JWT tokens | Validated by API Gateway authorizers for all requests|

### 5.2.5 CloudFront Origin Access Control

All access to S3 buckets must flow through CloudFront Origin Access Control (OAC). Requests are rejected unless they originate from the CloudFront distribution. This prevents direct and unauthorized S3 access to Restricted data (dashcam media, fleet reports, etc). Requests must be properly authenticated through the access token generator function to receive the CloudFront signed URL.

### 5.2.6 VPC Topology

All application workloads run inside private subnets with no internet ingress allowed. A NAT Gateway in the public subnet provides internet egress for AWS public zone or private resources. Gateway endpoints for S3 and DynamoDB keep data traffic off the public internet. Kinesis Data Stream and Kinesis Firehose Interface Endpoints are deployed to provide a dedicated private path from the Telemetry Consumer Service to Kinesis.

VPC interface endpoints for Secrets Manager, CloudWatch Logs, STS, and ECR are considerations to enhance architecture hardening, however, is deferred at lower scale. All services cache secrets into its memory at startup to limit Secrets Manager requests. Traffic egressing through the NAT gateway is TLS encrypted and relatively low risk. 

## 5.3 Identity and Access Management

### 5.3.1 Authentication and JWT Claims
Cognito issues JWT tokens that get validated by API Gateway authorizers. A Cognito Pre-token lambda function injects custom claims of `organizationId`, `role`, and `pseudoVINs` (as a list, supporting multi-vehicle users) into the ID token. Access to sensitive resources requires a temporary resource-scoped token generated by the Token Generator function.

### 5.3.2 Role-Based Access Control (RBAC)

Five roles are enforced by the API Handler lambda function. Each role is injected as a JWT claim and validated on every request.

| Role | Scope | Representative Permissions |
|---|---|---|
| Owner | Full account control | All permissions to account, organization, and vehicle management |
| Admin  | Operational administration | Manage members, drivers, vehicle assignments, geofences, alerts, and fleet reports. Restricted ownership permission. |
| Manager | Fleet oversight | View all fleet data, generate reports, acknowledge alerts. Cannot modify org structure or user roles. |
| Driver | Vehicle-scoped access | View own assigned vehicles only. Access trip history, driving scores, and maintenance alerts for assigned vehicles. |
| Viewer | Read-only | View live dashboard and historical data for assigned vehicles. No write access. |

### 5.3.3 Separation of Duties

IAM boundary policies are assigned to IAM administrators to prevent privilege escalation. Administrators cannot grant themselves or other principals permissions beyond their own boundary policy scope.

Dual-person access controls are planned for sensitive data access. Accessing protected dashcam media, for example, will require two separate privileged actions (`kms:Decrypt` for decryption and `s3:GetObject` for data retrieval). An internal platform will be required to mediate the combination of two admin IAM permissions to grant access.

### 5.3.4 Service Control Policies (SCPs)

SCPs apply guardrails across all accounts (production, staging, development) that cannot be bypassed:

- SCP-1: Region restrictions. Resources can only be created in us-east-1 or us-west-2. Global services such as Route53 are excluded.
- SCP-2: Root account lockdown. Root account usage is restricted to specific workflows such as account recovery or billing. Root credentials are stored securely and can only be accessed through hardware MFA (break glass).
- SCP-3: MFA for destructive actions. Denies deletion of infrastructure resources (S3, DynamoDB, etc) unless the user has authenticated with MFA.
- SCP-4: Security control tamper protection. Restricts any attempt to disable or terminate security controls such as CloudTrail, GuardDuty, and WAF.

## 5.4 Logging, Monitoring, and Incident Response
### 5.4.1 Audit Trails

CloudTrail captures all AWS API activity and stores trails in S3 for one year. The bucket blocks any attempts to delete data manually and prevents any principal other than CloudTrail to write data. CloudTrail writes data with SHA-256 hashes to detect unauthorized modification or tampering of data. Additionally, the bucket is configured in compliance mode to prevent premature deletion or overwriting of data. The S3 bucket effectively uses the WORM *(write-once-read-many)* framework and prevents any attempt to manipulate data.

Full CloudTrail Bucket Hardening:

| Protection | Configuration | Purpose |
|---|---|---|
| S3 Object Lock (Compliance mode) | 365-day retention | Data cannot be deleted, modified, or overwritten by anything (including Root).  |
| Deny DeleteObject - policy | Explicit deny on `s3:DeleteObject` and `s3:DeleteObjectVersion` | Negligible due to compliance mode but prevents principals from deleting data |
| Deny non-CloudTrail writes - policy | Explicit deny on writes NOT by `cloudtrail.amazonaws.com` | Prevents data from being injected by other principals |
| Deny policy modification - policy | Only specific IAM admin roles can modify the bucket policies | Prevents unauthorized policy changes. Compliance mode is permanent so policy modifications cannot enable tampering. |
| Block Public Access | All public access blocked | Prevents unauthorized access |
| Versioning | Enabled (required for Object Lock) | Preserves all versions of log objects |
| KMS encryption | SSE-KMS with platform data CMK | Encrypts logs at rest with auditable key usage |

CloudWatch metric filters monitor seven sensitive operations with SNS alerts:

- `vin-mapping` table access
- Root account usage
- IAM policy changes
- S3 policy changes
- KMS key modifications
- HMAC key secret access (anomalous patterns)
- OEM Command Proxy error rate spike

### 5.4.2 Threat Detection

GuardDuty runs threat detection across VPC flow logs, CloudTrail management events, and DNS logs. Severe findings trigger SNS alerts to admins. GuardDuty is configured with S3 protection and monitors the CloudTrail logs S3 bucket for API operations. It catches exfiltration attempts, suspicious access, and data destruction events. GuardDuty also monitors other sensitive buckets such as dashcam media for unusual access patterns.

| Plan | Data Source | Detects |
|---|---|---|
| Foundational threat detection | CloudTrail management events, VPC Flow Logs, DNS logs | Account compromise, unauthorized API calls, network anomalies |
| S3 Protection | CloudTrail S3 data events (`GetObject`, `PutObject`, `DeleteObject`, `ListObjects`) | Data exfiltration, anomalous access, bulk downloads, unauthorized data destruction |

### 5.4.3 Incident Response Triggers
Security events are categorized by severity levels and warrant different incident response procedures. A brief example of what production incident response runbooks may entail:

| Alert Severity | Trigger Examples | Escalation Path | Initial Containment |
|---|---|---|---|
| Critical | GuardDuty high-severity findings, data exfiltration detection, security control tampering attempts, `vin-mapping` unauthorized access, HMAC key anomalous access | Immediate page to on-call security engineer, security lead notification within 15 minutes | Isolate compromised role, revoke temporary credentials, execute key rotation workflow |
| High | Failed secret rotation, OEM Command Proxy error spike | Alert to security channel, security engineer review within 1 hour | Restrict access to affected resources until investigation is complete |
| Medium | IAM policy changes, S3 policy changes, KMS key modifications, root account usage | Alert to security channel, review within 4 hours | Log and review, revert unauthorized changes |

## 5.5 Encryption Strategy

### 5.5.1 Encryption at Rest and In Transit

Sensitive S3 buckets use dedicated KMS customer managed keys (CMK) with bucket keys enabled and automatic annual rotations. Other operational S3 buckets use S3 AES-256 keys. Kinesis Data Stream and Firehose use KMS CMK for encryption at rest and in transit. All DynamoDB tables use KMS managed keys and integrate with CloudTrail for audit visibility. The managed key allows for easy integration with less KMS policy overhead. Transitioning to CMKs is a consideration but only for tables that warrant high security like `vin-mapping`. ElastiCache Valkey utilizes service-managed keys for encryption at rest and in transit.

TLS is provided through ACM certificates and enforced through CloudFront and API Gateway. Vehicle to cloud communication is encrypted with IoT Device Certificates and mTLS.

### 5.5.2 KMS Key Policies

The platform uses a data CMK and a telemetry CMK. Each key is provisioned with least privilege policies. The data CMK covers sensitive S3 buckets (dashcam, telemetry archive, reports) and SNS topic encryption. Only services that write or publish to these resources are granted `GenerateDataKey` permissions, and services that need to read from these resources are granted `Decrypt` permissions. The telemetry CMK covers the Kinesis Data Stream and Kinesis Firehose resources. The IoT Core rule role is granted write only access to Kinesis Data Stream and the Telemetry Consumer Service is granted read only access to Kinesis Data Stream and write only access to Kinesis Firehose.

> Note: The Telemetry Consumer Service requires `iot:Publish` permission to send MQTT commands to the dashcam Edge Device via IoT Core if integrating dashcam with the platform, see *Technical Design Section 4.5.*

## 5.6 Secrets Management
Secrets manager stores sensitive credentials and secrets that resources retrieve typically at boot. Each resource accessing secrets are granted the minimal IAM permissions to retrieve only the exact secret it requires. 

---
[Technical Design](04-technical-design.md) | [Next: Capacity & Performance Planning](06-capacity-and-performance-planning.md)