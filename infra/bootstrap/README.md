# Bootstrap

Crea los recursos base que necesita el resto del repositorio: bucket S3 de estado de Terraform con CMK de KMS, proveedor OIDC de GitHub, roles de GitHub Actions (`github-terraform-plan` y `github-terraform-apply`) en la cuenta DevOps, y los roles `chatbot-plan-role` y `chatbot-deploy-role` en las cinco cuentas destino (networking, workload-dev, workload-pre, workload-prod, dr).

Este módulo se aplica una sola vez y de forma manual, en local. No lo ejecuta el CI.

## Prerequisites

- Terraform >= 1.10.
- Credenciales locales con permisos de administrador en la cuenta DevOps (sin claves estáticas en el repositorio; usa SSO o un rol temporal).
- Acceso al rol `OrganizationAccountAccessRole` en las cinco cuentas destino, que asumen los providers con alias.
- Un fichero `terraform.tfvars` local (no se commitea) con las variables de `variables.tf`: IDs de las seis cuentas, `state_bucket_name`, `github_org`, `github_repo`, `allowed_principals`, `break_glass_role_arn`, `bootstrap_operator_arn` y las etiquetas.
- Si el proveedor OIDC de GitHub ya existe en la cuenta DevOps, define `create_github_oidc_provider = false`.

## Uso inicial

1. Prepara las credenciales locales descritas en Prerequisites.
2. Ejecuta `terraform init`. Arranca con `backend "local" {}` definido en `backend.tf`.
3. Ejecuta `terraform plan` y revisa el resultado. Después ejecuta `terraform apply`, que crea la CMK, el bucket S3, el proveedor OIDC y todos los roles IAM.

## Migración del estado a S3

4. Edita `backend.tf` y sustituye `backend "local" {}` por:

   ```hcl
   backend "s3" {
     bucket       = "<state_bucket_name>"
     key          = "infra/bootstrap/terraform.tfstate"
     region       = "eu-west-1"
     encrypt      = true
     kms_key_id   = "<clave_arn>"
     use_lockfile = true
   }
   ```

   `<state_bucket_name>` y `<clave_arn>` salen de los outputs `state_bucket_name` y `state_kms_key_arn`.

5. Ejecuta `terraform init -migrate-state`. Terraform copia el estado local al bucket S3.
6. Comprueba que el estado existe: `aws s3 ls s3://<state_bucket_name>/infra/bootstrap/`.

Tras la migración, elimina el `terraform.tfstate` local.

## Desbloqueo de lock huérfano

Con `use_lockfile = true` el bloqueo es un objeto `<key>.tflock` en el mismo bucket. Si un proceso termina de forma anormal, el objeto puede quedar huérfano y bloquear nuevas ejecuciones.

1. Ejecuta `terraform force-unlock <LOCK_ID>`. El `LOCK_ID` aparece en el mensaje de error.
2. Si no es posible, borra el objeto: `aws s3 rm s3://<state_bucket_name>/infra/bootstrap/terraform.tfstate.tflock`.

Antes de desbloquear, confirma que ningún otro proceso de Terraform está en ejecución.

## Nota: fallo del primer `terraform apply`

El primer `terraform apply` puede fallar al crear la política de la CMK con `MalformedPolicyDocument`. La causa es la propagación eventual de IAM: la política referencia principals (roles) recién creados que aún no son visibles para KMS. Basta con repetir `terraform apply`.

## Outputs

| Output | Descripción |
|---|---|
| `state_bucket_name` | Nombre del bucket S3 de estado |
| `state_bucket_arn` | ARN del bucket de estado |
| `state_kms_key_arn` | ARN de la CMK del estado |
| `github_plan_role_arn` | ARN del rol `github-terraform-plan` |
| `github_apply_role_arn` | ARN del rol `github-terraform-apply` |
| `chatbot_plan_role_arns` | Mapa cuenta → ARN de `chatbot-plan-role` |
| `chatbot_deploy_role_arns` | Mapa cuenta → ARN de `chatbot-deploy-role` |
