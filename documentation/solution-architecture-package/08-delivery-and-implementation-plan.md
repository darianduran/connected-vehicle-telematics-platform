# 8.0 Delivery & Implementation Plan
## 8.1 Infrastructure as Code

The platform infrastructure is defined in Terraform under `iac/`.

### 8.1.1 Environment Configuration

Environment-specific behavior is controlled through `tfvars` files. Key variables that differ between environments:

| Variable | Dev | Prod |
|---|---|---|
| `env` | `dev` | `prod` |
| `domain_name` | `dev.fleet.example.com` | `prod.fleet.example.com` |
| `route53_zone_id` | `{dev-hosted-zone-ID}` | `{prod-hosted-zone-ID}` |
| `enable_deletion_protection` | `false` | `true` |
| `enable_global_tables` | `false` | `true` |
| `enable_signed_urls` | `false` | `true` |
| `cloudfront_public_key_pem` | `-` | `{public-key-pem}` |
| `cloudfront_private_key_arn` | `-` | `{private-key-secret-arn}` |
| `vpc_cidr` | `{dev-vpc-cidr}` | `{prod-vpc-cidr}` |
| `deploy_ecs_services` | `true` | `true` |
| `image_tag_consumer` | `latest` | `latest` |
| `image_tag_sse` | `latest` | `latest` |

> Note: 
>
> `cloudfront_*` variables are dependent on `enable_signed_urls` being set to true
> `deploy_ecs_services` is set to false during the initial application. `image_tag_*` depends on `deploy_ecs_services` and is skipped. The variable is set to true before the second application.

### 8.1.2 Deployment Procedure

Deployment follows a four-step procedure:

1. Prerequisites 
   
2. Bootstrap
   
3. Initial Infrastructure Application
   
4. Deploy Applications & Reapply Infrastructure 

**Step 1 - Prerequisites:**
1. Install AWS CLI and authenticate using `aws configure` or `aws sso login`
   
2. Install Terraform
   
3. Register a Route53 domain manually and paste the zone_id into the `route53_zone_id` field in the `tfvars` file
   
4. Generate an RSA-2048 key pair. Manually create a secret in Secrets Manager of the private key, note the secret ARN. Paste the public key PEM and private key secret ARN into `tfvars`

> Note: Registering the domain with Route53 is optional. Testing has been done with CloudFront without any issues, the Terraform IaC just needs to be updated.
  
**Step 2 - Bootstrap**

The bootstrap stack provisions the S3 backend bucket for Terraform state.

1. Configure `iac/bootstrap/variables.tf` with the app name and environment
   
2. Run `terraform init` and `terraform apply` from `iac/bootstrap/`
   
3. Confirm the `tfstate_bucket` was deployed in S3 through the console or AWS CLI (`aws s3 ls`)

**Step 3 - Initial Infrastructure Application**

This step provisions all AWS resources except ECS services. Lambda functions are deployed as with placeholder stubs and ECS services are disabled since the container images don't exist in ECR yet.

1. Make a copy of the tfvars file `cp {env}.tfvars.example {env}.tfvars` and populate the variable values.
   
2. Configure the S3 backend in `versions.tf` using the bucket from Phase 1
   
3. Run `terraform init` and `terraform apply -var-file={env}.tfvars`
   
4. Collect the ECR repository URI and S3 console bucket name from the Terraform output logs

**Step 4 - Application Deploy & Reapply Infrastructure**

This step builds and deploys the application code. Terraform is reapplied to activate ECS services and replace the Lambda stubs with the real functions. 

1. Build and push container images (Telemetry Consumer Service, SSE Streaming Service) to ECR

2. Deploy Lambda function packages
   
3. Upload the frontend build to the S3 console bucket
   
4. Set `deploy_ecs_services = true` and update `image_tag_consumer` / `image_tag_sse` to the pushed tags (default is `latest`)
   
5. Run `terraform apply -var-file=<env>.tfvars` to create ECS services and finalize the deployment
   
6. Apply an invalidation of `/*` in CloudFront to propagate the frontend.

## 8.2 Deployment Strategies

| Component | Strategy | Details |
|---|---|---|
| ECS Services | Rolling update | Min healthy 100%, max 200%. Health check grace 60s, deregistration delay 30s. |
| Telemetry Consumer Service (ECS) | Rolling update with shard lease handoff | Requires KCL shard lease transfer during rolling update. Brief duplicate processing absorbed by downstream idempotency. |
| Lambda | Artifact replacement | Rollback by redeploying previous package. |
| Frontend (S3 + CloudFront) | Sync + invalidation | Propagates globally in 5-10 min. |

### 8.2.1 Rollback Procedures

| Component | Procedure |
|---|---|
| ECS | Redeploy previous task definition revision. |
| Lambda | Redeploy previous zip via `update-function-code`. |
| Terraform | Revert in Git, run `terraform plan`, then apply. |
| Frontend | Sync previous build to S3, then run CloudFront invalidation. |

---
[Resilience & Disaster Recovery](07-resilience-and-disaster-recovery.md) | [Next: Operations & Support](09-operations-and-support.md)