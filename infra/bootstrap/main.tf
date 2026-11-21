# NOTE: local.target_accounts is defined in iam_policies.tf (single definition).

# ---------------------------------------------------------------------------
# KMS: customer managed key for the Terraform state bucket (DevOps account)
# ---------------------------------------------------------------------------
resource "aws_kms_key" "state" {
  description             = "CMK for the Terraform state bucket ${var.state_bucket_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 10

  # KMS rejects policies that name principals that do not exist yet; the policy
  # uses locals (no attribute references), so this adds ordering without a cycle.
  depends_on = [aws_iam_role.github_plan, aws_iam_role.github_apply]

  # All principal ARNs come from variables/locals (not from aws_iam_role attributes)
  # to avoid a dependency cycle with the roles and keep the ARNs known at plan time.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountRootAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.devops_account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowStateKeyUsage"
        Effect = "Allow"
        Principal = {
          AWS = [
            local.github_plan_role_arn,
            local.github_apply_role_arn,
            var.bootstrap_operator_arn,
            var.break_glass_role_arn,
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_kms_alias" "state" {
  name          = local.state_kms_alias
  target_key_id = aws_kms_key.state.key_id
}

# ---------------------------------------------------------------------------
# S3: Terraform state bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  # Versioning must exist before lifecycle rules on noncurrent versions
  depends_on = [aws_s3_bucket_versioning.tfstate]

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = local.bucket_policy_json

  # Apply the public access block first to avoid concurrent policy/PAB conflicts
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# ---------------------------------------------------------------------------
# GitHub OIDC provider: created here or reused if it already exists in the account
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  arn = "arn:aws:iam::${var.devops_account_id}:oidc-provider/token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}
