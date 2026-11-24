# Target-account roles assumed by the GitHub OIDC roles living in the DevOps account.

# Read-only role used by plan/drift pipelines.
resource "aws_iam_role" "chatbot_plan" {
  name        = "chatbot-plan-role"
  description = "Read-only role for terraform plan in account ${var.account_name}"

  # Trust only the exact GitHub plan role ARN (no wildcards).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { AWS = var.github_plan_arn }
      }
    ]
  })

  tags = {
    Name        = "chatbot-plan-role"
    AccountName = var.account_name
  }
}

# Role used by the apply pipeline to deploy resources.
resource "aws_iam_role" "chatbot_deploy" {
  name        = "chatbot-deploy-role"
  description = "Deployment role for terraform apply in account ${var.account_name}"

  # Trust only the exact GitHub apply role ARN (no wildcards).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { AWS = var.github_apply_arn }
      }
    ]
  })

  tags = {
    Name        = "chatbot-deploy-role"
    AccountName = var.account_name
  }
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.chatbot_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Placeholder policy with a temporary minimal permission; extended in later specs.
resource "aws_iam_policy" "deploy_base" {
  name        = "chatbot-deploy-base"
  description = "Placeholder base policy for the deploy role in account ${var.account_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowGetCallerIdentity"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*" # sts:GetCallerIdentity does not support resource-level restrictions
      }
    ]
  })

  tags = {
    Name        = "chatbot-deploy-base"
    AccountName = var.account_name
  }
}

resource "aws_iam_role_policy_attachment" "deploy_base" {
  role       = aws_iam_role.chatbot_deploy.name
  policy_arn = aws_iam_policy.deploy_base.arn
}
