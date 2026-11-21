# Módulo kms

Crea una clave KMS gestionada por el cliente (CMK) con rotación anual activada y un alias asociado. Se instancia una vez por cuenta y propósito (por ejemplo `data`, `logs`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.73 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.73 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alias_name"></a> [alias\_name](#input\_alias\_name) | Alias of the KMS key. Must start with 'alias/'. | `string` | n/a | yes |
| <a name="input_deletion_window_in_days"></a> [deletion\_window\_in\_days](#input\_deletion\_window\_in\_days) | Waiting period, in days, before the KMS key is deleted after destruction (7-30). | `number` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | Description of the KMS key (1-256 characters). | `string` | n/a | yes |
| <a name="input_policy"></a> [policy](#input\_policy) | JSON key policy for the KMS key. If empty, the AWS default key policy is used. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the KMS key. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alias_arn"></a> [alias\_arn](#output\_alias\_arn) | ARN of the KMS key alias. |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | ARN of the KMS key. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | ID of the KMS key. |

## Resources

| Name | Type |
|------|------|
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
<!-- END_TF_DOCS -->
