# ADR-005: VIN Pseudonymization at the Ingestion Layer

## Context

VINs are unique vehicle identifiers classified as PII. They can be linked to the vehicle owner and expose location history and driving patterns. The original implementation stored raw VINs in all DynamoDB tables, S3 buckets, and CloudWatch logs. I caught this while debugging a Lambda function and saw raw VINs sitting in plaintext in the logs. KMS encrypts data at rest, but anyone with read access to a table or log group could see them directly.

## Decision

Apply HMAC-SHA256 pseudonymization to raw VINs at the ingestion boundary before any data reaches databases, caches, or logs. A dedicated `vin-mapping` DynamoDB table stores the bidirectional mapping, restricted to a single admin IAM role with full CloudTrail data event logging.

## Rationale

HMAC-SHA256 provides deterministic output for use as a partition key, irreversibility without the secret key, fixed-length output, and single-function-call simplicity.

## Rejected Alternatives

- **Raw VIN + KMS at rest:** Does not protect against authorized access; logs and exports contain raw VINs.
- **AES-256 encryption:** Cannot serve as a partition key; decryption required on every read.
- **SHA-256 hash (no key):** Rainbow table attack can recover all VINs.
- **Tokenization via CloudHSM:** High cost; requires API calls on every operation.

## Consequences

- Raw VINs are contained to the ingestion layer. All downstream stores, caches, logs, and API responses use only pseudoVINs.
- The `vin-mapping` table is the single point of reverse resolution, requiring restricted IAM, CloudTrail data event logging, and deletion protection. See ADR-009 for the table's isolation rationale.
- HMAC key rotation requires coordinated re-pseudonymization of DynamoDB tables and S3 buckets.

## Status

Accepted, 09 JAN 2026

**Reevaluation triggers:**
- Regulatory changes requiring full anonymization instead of pseudonymization
- Key compromise events
- Fleet scale increases enough to impact HMAC computation overhead
