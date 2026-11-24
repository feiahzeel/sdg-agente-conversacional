# Verifies P-IAM-01..04 and P-S3-02 on the policy documents of the bootstrap.
# Locals are not addressable from a run block, so the assertions read the
# policy documents through the resources that consume them (known at plan time
# because they are built from variables only). No AWS credentials are needed.

mock_provider "aws" {}
mock_provider "aws" { alias = "networking" }
mock_provider "aws" { alias = "workload_dev" }
mock_provider "aws" { alias = "workload_pre" }
mock_provider "aws" { alias = "workload_prod" }
mock_provider "aws" { alias = "dr" }

variables {
  state_bucket_name           = "chatbot-test-tfstate"
  devops_account_id           = "111111111111"
  networking_account_id       = "222222222222"
  workload_dev_account_id     = "333333333333"
  workload_pre_account_id     = "444444444444"
  workload_prod_account_id    = "555555555555"
  dr_account_id               = "666666666666"
  github_org                  = "my-org"
  github_repo                 = "sdg-agente-conversacional"
  create_github_oidc_provider = true
  allowed_principals          = ["arn:aws:iam::111111111111:role/BreakGlass"]
  break_glass_role_arn        = "arn:aws:iam::111111111111:role/BreakGlass"
  bootstrap_operator_arn      = "arn:aws:iam::111111111111:role/AdminRole"
  enable_vpn                  = false
  project                     = "chatbot"
  environment                 = "bootstrap"
  owner                       = "platform-team"
  cost_center                 = "CC-001"
  data_classification         = "internal"
}

# P-IAM-01: the plan role has no write actions.
# Definition of "write action": any action whose name starts with a mutating
# verb (Create, Put, Delete, Update, Attach, Detach, Set, Tag, Untag, Modify,
# Start, Stop, Run, Terminate, Import, Restore) or any wildcard action.
# Accepted exceptions:
#   - s3 write actions only on objects ending in ".tflock" (use_lockfile).
#   - kms:Encrypt and kms:GenerateDataKey: required to write the encrypted
#     state lockfile; they do not mutate infrastructure.
#   - sts:AssumeRole is not a write verb (it is covered by P-IAM-03).
run "p_iam_01_plan_role_no_write_actions" {
  command = plan

  assert {
    condition = !anytrue(flatten([
      for stmt in jsondecode(aws_iam_policy.github_plan.policy).Statement : [
        for action in flatten([try(tolist(stmt.Action), [stmt.Action])]) :
        (
          can(regex(":\\*$|^\\*$", action))
          || (
            can(regex(":(Create|Put|Delete|Update|Attach|Detach|Set|Tag|Untag|Modify|Start|Stop|Run|Terminate|Import|Restore)", action))
            && !(
              startswith(action, "s3:")
              && alltrue([
                for r in flatten([try(tolist(stmt.Resource), [stmt.Resource])]) :
                endswith(r, ".tflock")
              ])
            )
          )
        )
      ]
    ]))
    error_message = "P-IAM-01: the plan role policy contains write actions outside .tflock objects."
  }
}

# P-IAM-02: the apply role has no workload service permissions.
run "p_iam_02_apply_role_no_workload_perms" {
  command = plan

  assert {
    condition = !anytrue(flatten([
      for stmt in jsondecode(aws_iam_policy.github_apply.policy).Statement : [
        for action in flatten([try(tolist(stmt.Action), [stmt.Action])]) :
        can(regex("^(ec2|ecs|rds|elasticloadbalancing|route53|bedrock|dynamodb|iam):", action))
      ]
    ]))
    error_message = "P-IAM-02: the apply role policy contains workload service actions."
  }
}

# P-IAM-03: the plan role can only assume chatbot-plan-role in the target accounts.
run "p_iam_03_plan_role_assumes_only_plan_roles" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for stmt in jsondecode(aws_iam_policy.github_plan.policy).Statement : [
        for r in flatten([try(tolist(stmt.Resource), [stmt.Resource])]) :
        endswith(r, ":role/chatbot-plan-role")
        if contains(flatten([try(tolist(stmt.Action), [stmt.Action])]), "sts:AssumeRole")
      ]
    ]))
    error_message = "P-IAM-03: sts:AssumeRole in the plan policy targets roles other than chatbot-plan-role."
  }

  assert {
    condition = anytrue(flatten([
      for stmt in jsondecode(aws_iam_policy.github_plan.policy).Statement : [
        contains(flatten([try(tolist(stmt.Action), [stmt.Action])]), "sts:AssumeRole")
      ]
    ]))
    error_message = "P-IAM-03: the plan policy has no sts:AssumeRole statement."
  }
}

# P-IAM-04: the apply role can only assume chatbot-deploy-role in the target accounts.
run "p_iam_04_apply_role_assumes_only_deploy_roles" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for stmt in jsondecode(aws_iam_policy.github_apply.policy).Statement : [
        for r in flatten([try(tolist(stmt.Resource), [stmt.Resource])]) :
        endswith(r, ":role/chatbot-deploy-role")
        if contains(flatten([try(tolist(stmt.Action), [stmt.Action])]), "sts:AssumeRole")
      ]
    ]))
    error_message = "P-IAM-04: sts:AssumeRole in the apply policy targets roles other than chatbot-deploy-role."
  }

  assert {
    condition = anytrue(flatten([
      for stmt in jsondecode(aws_iam_policy.github_apply.policy).Statement : [
        contains(flatten([try(tolist(stmt.Action), [stmt.Action])]), "sts:AssumeRole")
      ]
    ]))
    error_message = "P-IAM-04: the apply policy has no sts:AssumeRole statement."
  }
}

# P-S3-02: the state bucket policy denies requests without TLS.
run "p_s3_02_tls_enforced" {
  command = plan

  assert {
    condition = anytrue([
      for stmt in jsondecode(aws_s3_bucket_policy.tfstate.policy).Statement :
      stmt.Effect == "Deny" && try(stmt.Condition.Bool["aws:SecureTransport"], "") == "false"
    ])
    error_message = "P-S3-02: the bucket policy has no Deny statement on aws:SecureTransport = false."
  }
}
