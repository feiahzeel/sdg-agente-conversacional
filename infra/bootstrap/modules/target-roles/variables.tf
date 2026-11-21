variable "github_plan_arn" {
  description = "ARN of the GitHub OIDC plan role (chatbot-github-plan) allowed to assume the target plan role."
  type        = string
}

variable "github_apply_arn" {
  description = "ARN of the GitHub OIDC apply role (chatbot-github-apply) allowed to assume the target deploy role."
  type        = string
}

variable "account_name" {
  description = "Logical name of the target account (e.g. networking, devops, workload-dev), used for naming and tagging."
  type        = string
}

# Reserved by the foundation spec (req. VPN permissions only when true); consumed by the networking spec, so intentionally unused for now.
# tflint-ignore: terraform_unused_declarations
variable "enable_vpn" {
  description = "Whether the Site-to-Site VPN is enabled; allows the deploy role to manage VPN resources when true."
  type        = bool
  default     = false
}
