# GitHub Actions roles (DevOps account). Role names must match
# local.github_plan_role_arn / local.github_apply_role_arn in iam_policies.tf.

locals {
  github_repo_ref = "repo:${var.github_org}/${var.github_repo}"
}

resource "aws_iam_role" "github_plan" {
  name = "github-terraform-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = local.github_oidc_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "${local.github_repo_ref}:pull_request",
              "${local.github_repo_ref}:ref:refs/heads/main",
            ]
          }
        }
      },
    ]
  })
}

resource "aws_iam_role" "github_apply" {
  name = "github-terraform-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = local.github_oidc_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "${local.github_repo_ref}:ref:refs/heads/main",
              "${local.github_repo_ref}:environment:*",
            ]
          }
        }
      },
    ]
  })
}

resource "aws_iam_policy" "github_plan" {
  name   = "github-terraform-plan"
  policy = local.github_plan_policy_json
}

resource "aws_iam_policy" "github_apply" {
  name   = "github-terraform-apply"
  policy = local.github_apply_policy_json
}

resource "aws_iam_role_policy_attachment" "github_plan" {
  role       = aws_iam_role.github_plan.name
  policy_arn = aws_iam_policy.github_plan.arn
}

resource "aws_iam_role_policy_attachment" "github_apply" {
  role       = aws_iam_role.github_apply.name
  policy_arn = aws_iam_policy.github_apply.arn
}
