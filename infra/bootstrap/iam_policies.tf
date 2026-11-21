# All ARNs below are built from variables only (never from resource attributes),
# so these locals are known at plan time and can be asserted in terraform test.

locals {
  # Target accounts (single definition; main.tf must not redefine it)
  target_accounts = {
    networking    = { account_id = var.networking_account_id, region = "eu-west-1" }
    workload_dev  = { account_id = var.workload_dev_account_id, region = "eu-west-1" }
    workload_pre  = { account_id = var.workload_pre_account_id, region = "eu-west-1" }
    workload_prod = { account_id = var.workload_prod_account_id, region = "eu-west-1" }
    dr            = { account_id = var.dr_account_id, region = "eu-central-1" }
  }

  state_bucket_arn      = "arn:aws:s3:::${var.state_bucket_name}"
  github_plan_role_arn  = "arn:aws:iam::${var.devops_account_id}:role/github-terraform-plan"
  github_apply_role_arn = "arn:aws:iam::${var.devops_account_id}:role/github-terraform-apply"

  chatbot_plan_role_arns = [
    for name, acct in local.target_accounts :
    "arn:aws:iam::${acct.account_id}:role/chatbot-plan-role"
  ]
  chatbot_deploy_role_arns = [
    for name, acct in local.target_accounts :
    "arn:aws:iam::${acct.account_id}:role/chatbot-deploy-role"
  ]

  # KMS: wildcard key resource restricted to the state key through its alias
  state_kms_resource = "arn:aws:kms:eu-west-1:${var.devops_account_id}:key/*"
  state_kms_alias    = "alias/chatbot-devops-tfstate"

  github_plan_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.state_bucket_arn]
      },
      {
        Sid      = "StateRead"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${local.state_bucket_arn}/*"]
      },
      {
        Sid      = "StateLockfile"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = ["${local.state_bucket_arn}/*.tflock"]
      },
      {
        Sid      = "StateKmsUse"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource = local.state_kms_resource
        Condition = {
          "ForAnyValue:StringEquals" = {
            "kms:ResourceAliases" = [local.state_kms_alias]
          }
        }
      },
      {
        Sid      = "AssumeTargetPlanRoles"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = local.chatbot_plan_role_arns
      },
    ]
  })

  github_apply_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.state_bucket_arn]
      },
      {
        Sid      = "StateReadWrite"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${local.state_bucket_arn}/*"]
      },
      {
        Sid      = "StateLockfile"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = ["${local.state_bucket_arn}/*.tflock"]
      },
      {
        Sid      = "StateKmsUse"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource = local.state_kms_resource
        Condition = {
          "ForAnyValue:StringEquals" = {
            "kms:ResourceAliases" = [local.state_kms_alias]
          }
        }
      },
      {
        Sid    = "EcrAuthToken"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        # GetAuthorizationToken does not support resource-level permissions
        Resource = "*"
      },
      {
        Sid    = "EcrRepositories"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:CreateRepository",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:PutLifecyclePolicy",
          "ecr:SetRepositoryPolicy",
          "ecr:TagResource",
          "ecr:UploadLayerPart",
        ]
        Resource = ["arn:aws:ecr:eu-west-1:${var.devops_account_id}:repository/chatbot-*"]
      },
      {
        Sid      = "AssumeTargetDeployRoles"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = local.chatbot_deploy_role_arns
      },
    ]
  })

  bucket_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid       = "DenyUnauthorizedPrincipals"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
        Condition = {
          ArnNotLike = {
            "aws:PrincipalArn" = concat(
              [
                local.github_plan_role_arn,
                local.github_apply_role_arn,
                var.break_glass_role_arn,
                var.bootstrap_operator_arn,
              ],
              var.allowed_principals,
            )
          }
        }
      },
    ]
  })
}
