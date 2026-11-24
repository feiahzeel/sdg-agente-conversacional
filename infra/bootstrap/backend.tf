# Initial local state: the S3 bucket does not exist before the first apply.
# After apply, replace this block by the S3 backend described in README.md
# and run `terraform init -migrate-state`.
terraform {
  backend "local" {}
}
