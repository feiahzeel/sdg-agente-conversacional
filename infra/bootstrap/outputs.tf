output "state_bucket_name" {
  description = "Name of the S3 bucket that stores the Terraform state."
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket that stores the Terraform state."
  value       = aws_s3_bucket.tfstate.arn
}

output "state_kms_key_arn" {
  description = "ARN of the customer managed KMS key that encrypts the Terraform state bucket."
  value       = aws_kms_key.state.arn
}

output "github_plan_role_arn" {
  description = "ARN of the github-terraform-plan role assumed by GitHub Actions through OIDC (plan and drift)."
  value       = aws_iam_role.github_plan.arn
}

output "github_apply_role_arn" {
  description = "ARN of the github-terraform-apply role assumed by GitHub Actions through OIDC (apply)."
  value       = aws_iam_role.github_apply.arn
}

output "chatbot_plan_role_arns" {
  description = "Map account name => ARN of the chatbot-plan-role (read-only) in each target account."
  value = {
    for name, acct in local.target_accounts :
    name => "arn:aws:iam::${acct.account_id}:role/chatbot-plan-role"
  }
}

output "chatbot_deploy_role_arns" {
  description = "Map account name => ARN of the chatbot-deploy-role in each target account."
  value = {
    for name, acct in local.target_accounts :
    name => "arn:aws:iam::${acct.account_id}:role/chatbot-deploy-role"
  }
}
