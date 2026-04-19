
provider "aws" { ## Primary region for the resources (must be us-east-1 for CloudFront / ACM.)
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}


## Uncomment this block if you want to change the default deployment region. Then point CloudFront/ACM resources to aws.edge alias
## provider "aws" { 
##   alias  = "edge"
##   region = var.edge_region
## 
##   default_tags {
##     tags = local.common_tags
##   }
## }


provider "aws" { ## DR region
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = local.common_tags
  }
}
