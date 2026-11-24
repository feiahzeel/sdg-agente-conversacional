variable "description" {
  description = "Description of the KMS key (1-256 characters)."
  type        = string

  validation {
    condition     = length(var.description) >= 1 && length(var.description) <= 256
    error_message = "description must be between 1 and 256 characters long."
  }
}

variable "deletion_window_in_days" {
  description = "Waiting period, in days, before the KMS key is deleted after destruction (7-30)."
  type        = number

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "alias_name" {
  description = "Alias of the KMS key. Must start with 'alias/'."
  type        = string

  validation {
    condition     = can(regex("^alias/[a-zA-Z0-9/_-]+$", var.alias_name))
    error_message = "alias_name must match ^alias/[a-zA-Z0-9/_-]+$."
  }
}

variable "policy" {
  description = "JSON key policy for the KMS key. If empty, the AWS default key policy is used."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to the KMS key."
  type        = map(string)
  default     = {}
}
