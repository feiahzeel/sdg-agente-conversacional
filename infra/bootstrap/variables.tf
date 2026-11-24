variable "state_bucket_name" {
  description = "Name of the S3 bucket that stores the Terraform state."
  type        = string

  validation {
    condition     = length(trimspace(var.state_bucket_name)) > 0
    error_message = "state_bucket_name must not be empty."
  }
}

variable "devops_account_id" {
  description = "AWS account ID of the DevOps account (12 digits)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.devops_account_id))
    error_message = "devops_account_id must be a 12-digit AWS account ID."
  }
}

variable "networking_account_id" {
  description = "AWS account ID of the Networking account (12 digits)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.networking_account_id))
    error_message = "networking_account_id must be a 12-digit AWS account ID."
  }
}

variable "workload_dev_account_id" {
  description = "AWS account ID of the Workload-Dev account (12 digits)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.workload_dev_account_id))
    error_message = "workload_dev_account_id must be a 12-digit AWS account ID."
  }
}

variable "workload_pre_account_id" {
  description = "AWS account ID of the Workload-Pre account (12 digits)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.workload_pre_account_id))
    error_message = "workload_pre_account_id must be a 12-digit AWS account ID."
  }
}

variable "workload_prod_account_id" {
  description = "AWS account ID of the Workload-Prod account (12 digits)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.workload_prod_account_id))
    error_message = "workload_prod_account_id must be a 12-digit AWS account ID."
  }
}

variable "dr_account_id" {
  description = "AWS account ID of the DR account (12 digits)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.dr_account_id))
    error_message = "dr_account_id must be a 12-digit AWS account ID."
  }
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository."
  type        = string

  validation {
    condition     = length(trimspace(var.github_org)) > 0
    error_message = "github_org must not be empty."
  }
}

variable "github_repo" {
  description = "Name of the GitHub repository allowed to assume the deployment roles."
  type        = string

  validation {
    condition     = length(trimspace(var.github_repo)) > 0
    error_message = "github_repo must not be empty."
  }
}

variable "create_github_oidc_provider" {
  description = "true creates the GitHub OIDC provider; false references an existing one."
  type        = bool
  default     = true
}

variable "allowed_principals" {
  description = "IAM principal ARNs explicitly allowed to access the state bucket."
  type        = list(string)

  validation {
    condition     = length(var.allowed_principals) >= 1
    error_message = "allowed_principals must contain at least one ARN."
  }
}

variable "break_glass_role_arn" {
  description = "ARN of the emergency (break-glass) role; it must always be part of allowed_principals."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::", var.break_glass_role_arn))
    error_message = "break_glass_role_arn must start with arn:aws:iam::."
  }
}

variable "bootstrap_operator_arn" {
  description = "ARN of the IAM role or user used to run terraform apply and init -migrate-state locally; excluded from the bucket policy deny via ArnNotLike."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:(role|user)/", var.bootstrap_operator_arn))
    error_message = "bootstrap_operator_arn must be an IAM role or user ARN (arn:aws:iam::<12 digits>:role|user/...)."
  }
}

variable "enable_vpn" {
  description = "Enables VPN permissions in chatbot-deploy-role."
  type        = bool
  default     = false
}

variable "project" {
  description = "Value of the Project tag."
  type        = string

  validation {
    condition     = length(trimspace(var.project)) > 0
    error_message = "project must not be empty or whitespace only."
  }
}

variable "environment" {
  description = "Value of the Environment tag."
  type        = string

  validation {
    condition     = length(trimspace(var.environment)) > 0
    error_message = "environment must not be empty or whitespace only."
  }
}

variable "owner" {
  description = "Value of the Owner tag."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty or whitespace only."
  }
}

variable "cost_center" {
  description = "Value of the CostCenter tag."
  type        = string

  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "cost_center must not be empty or whitespace only."
  }
}

variable "data_classification" {
  description = "Value of the DataClassification tag."
  type        = string

  validation {
    condition     = length(trimspace(var.data_classification)) > 0
    error_message = "data_classification must not be empty or whitespace only."
  }
}
