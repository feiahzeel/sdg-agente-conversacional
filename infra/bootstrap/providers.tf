locals {
  default_tags = {
    Project            = var.project
    Environment        = var.environment
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    DataClassification = var.data_classification
  }
}

# Default provider: DevOps account (credentials from the local environment or the GitHub role)
provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias  = "networking"
  region = "eu-west-1"

  assume_role {
    role_arn = "arn:aws:iam::${var.networking_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias  = "workload_dev"
  region = "eu-west-1"

  assume_role {
    role_arn = "arn:aws:iam::${var.workload_dev_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias  = "workload_pre"
  region = "eu-west-1"

  assume_role {
    role_arn = "arn:aws:iam::${var.workload_pre_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias  = "workload_prod"
  region = "eu-west-1"

  assume_role {
    role_arn = "arn:aws:iam::${var.workload_prod_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias  = "dr"
  region = "eu-central-1"

  assume_role {
    role_arn = "arn:aws:iam::${var.dr_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = local.default_tags
  }
}
