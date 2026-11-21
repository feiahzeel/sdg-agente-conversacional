# Implementation Plan: foundation

## Overview

Establece los cimientos del repositorio de infraestructura: estructura de carpetas, herramientas de calidad, módulo `kms` como patrón de referencia, bootstrap de Terraform (bucket S3 de estado, roles OIDC de GitHub, roles de despliegue multicuenta) y ADRs de decisión.

**Restricción crítica:** ninguna tarea requiere `terraform apply` ni credenciales AWS reales. Las verificaciones son `terraform validate`, `terraform test` con `mock_provider`, revisión de archivo o `git status`.

---

## Tasks

- [x] 1. Estructura de directorios del repositorio
  - Crear todas las carpetas definidas en `structure.md` que no existan aún: `.github/workflows/`, `docs/costes/`, `docs/inventario/`, `infra/bootstrap/modules/target-roles/`, `infra/bootstrap/tests/`, `infra/live/networking/eu-west-1/`, `infra/live/devops/eu-west-1/`, `infra/live/workload/dev/`, `infra/live/workload/pre/`, `infra/live/workload/prod/`, `infra/live/dr/eu-central-1/` y `tests/`
  - Añadir un archivo `.gitkeep` en cada carpeta que no contenga archivos `.tf`, `.tfvars`, `.tftest.hcl` ni `.md`; aplica a todos los módulos placeholder en `infra/modules/` y a las carpetas `live/` sin código aún
  - Crear las subcarpetas placeholder de `infra/modules/`: `tgw-hub`, `egress-inspection`, `central-endpoints`, `dns`, `workload-vpc`, `alb-oidc`, `ecs-platform`, `ecs-service`, `privatelink-service`, `aurora-pgvector`, `dynamodb-tracker`, `bedrock-kb`, `documents-bucket`, `ecr`, `powerbi-gateway`, `observability`, `budgets` — cada una con un único `.gitkeep`
  - Actualizar `.gitignore` para añadir las entradas Terraform (`.terraform/`, `*.tfstate`, `*.tfstate.backup`, `*.tflock`, `crash.log`, `*.auto.tfvars`, `override.tf`, `override.tf.json`) conservando las entradas preexistentes; NO añadir `.terraform.lock.hcl`
  - Añadir un único archivo `.gitkeep` en `.github/workflows/`; NO crear archivos `.yml` de workflow (un YAML vacío o stub es un workflow inválido que GitHub intentaría ejecutar)
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_
  - _Design: Componente 1 — Árbol completo_
  - **Verificación:** `git status` no muestra archivos `untracked` en ninguna carpeta del árbol; todas las carpetas listadas en el criterio 1.1 y 1.4 existen en el repositorio.

- [x] 2. Archivos de herramientas de calidad
  - Crear `.tflint.hcl` con el plugin AWS (`source = "github.com/terraform-linters/tflint-ruleset-aws"`, `version = "0.48.0"`), reglas `terraform_naming_convention`, `terraform_typed_variables`, `terraform_required_version` y `terraform_required_providers`
  - Crear `.checkov.yaml` con `directory: infra/`, `output-file-type: sarif`, sin filtro de severidad y sección `skip-check:` con `CKV_AWS_144`, `CKV2_AWS_62` y `CKV_AWS_18`, cada uno con comentario justificativo en la misma línea
  - Crear `.pre-commit-config.yaml` con hooks de `antonbabenko/pre-commit-terraform` en `rev: v1.99.4` (`terraform_fmt`, `terraform_validate`, `terraform_tflint`, `terraform_checkov`, `terraform_docs`) y `pre-commit/pre-commit-hooks` en `rev: v5.0.0` (`trailing-whitespace`, `end-of-file-fixer`, `check-merge-conflict`, `check-yaml`); cada hook incluye el campo `rev:` con versión concreta
  - Crear `.terraform-docs.yml` con la configuración de formato, secciones (inputs, outputs, resources) y modo de inserción en `README.md`
  - _Requirements: 6.1, 6.2, 6.3_
  - _Design: Componente 4 — Herramientas de calidad_
  - **Verificación:** revisión manual de que los cuatro archivos existen en la raíz con las versiones fijadas indicadas; `pre-commit run --all-files` pasa con código de salida 0 en entornos con las herramientas instaladas (verificación diferida a CI).

- [x] 3. Módulo `kms` — estructura e implementación
  - [x] 3.1 Crear `infra/modules/kms/versions.tf` con `required_version = ">= 1.10"` y el provider `hashicorp/aws ~> 6.73`
    - _Requirements: 7.6, 11.2_
    - _Design: Componente 3.1 — Estructura de archivos_
  - [x] 3.2 Crear `infra/modules/kms/variables.tf` con las variables `description` (string, validación longitud 1–256), `deletion_window_in_days` (number, validación 7–30 con mensaje de error), `alias_name` (string, validación regex `^alias/[a-zA-Z0-9/_-]+$`), `policy` (string, default `""`), `tags` (map(string), default `{}`); todas con `description` y `type` explícitos
    - _Requirements: 7.2, 7.3, 7.5_
    - _Design: Componente 3.2 — Interfaz del módulo_
  - [x] 3.3 Crear `infra/modules/kms/main.tf` con `aws_kms_key.this` (`enable_key_rotation = true`, `deletion_window_in_days = var.deletion_window_in_days`, `policy = var.policy != "" ? var.policy : null`, `tags = var.tags`) y `aws_kms_alias.this` (`name = var.alias_name`, `target_key_id = aws_kms_key.this.key_id`)
    - _Requirements: 7.2, 7.3, 7.9_
    - _Design: Componente 3.3 — Lógica interna_
  - [x] 3.4 Crear `infra/modules/kms/outputs.tf` con los outputs `key_id`, `key_arn` y `alias_arn`, cada uno con `description` no vacía
    - _Requirements: 7.4_
    - _Design: Componente 3.2 — Outputs_
  - [x] 3.5 Crear `infra/modules/kms/README.md` con al menos las secciones Requirements, Inputs, Outputs y Resources (contenido generado manualmente o mediante `terraform-docs`)
    - _Requirements: 7.1_
    - _Design: Componente 3.1 — Estructura de archivos_
  - **Verificación (tareas 3.1–3.5):** `terraform validate` en `infra/modules/kms/` termina con código de salida 0 y sin mensajes de error.

- [x] 4. Tests del módulo `kms`
  - [x] 4.1 Crear `infra/modules/kms/tests/kms_test.tftest.hcl` con `mock_provider "aws" {}` al nivel raíz del archivo y el bloque `run "valid_key"` (`command = plan`): bloque `variables {}` con `description = "Test KMS key"`, `deletion_window_in_days = 10`, `alias_name = "alias/chatbot-test"`; tres `assert` que verifiquen `aws_kms_key.this.enable_key_rotation == true`, `aws_kms_key.this.deletion_window_in_days >= 7 && aws_kms_key.this.deletion_window_in_days <= 30` y `startswith(aws_kms_alias.this.name, "alias/")`
    - _Requirements: 8.1, 8.2, 8.3, 8.4_
    - _Design: Componente 3.4 — run "valid_key"_
    - _Correctness Properties: P-KMS-01, P-KMS-02, P-KMS-03_
  - [x] 4.2 Añadir al mismo archivo el bloque `run "invalid_window"` (`command = plan`): bloque `variables {}` con `deletion_window_in_days = 5` y `expect_failures = [var.deletion_window_in_days]`
    - _Requirements: 8.5, 8.7_
    - _Design: Componente 3.4 — run "invalid_window"_
  - **Verificación (tareas 4.1–4.2):** `terraform test` ejecutado en `infra/modules/kms/` completa todos los bloques `run` con estado `pass` y código de salida 0, sin credenciales AWS en el entorno.

- [x] 5. Bootstrap — `versions.tf` y `variables.tf`
  - [x] 5.1 Crear `infra/bootstrap/versions.tf` con `required_version = ">= 1.10"` y el provider `hashicorp/aws ~> 6.73`
    - _Requirements: 11.1_
    - _Design: Componente 2.1 — versions.tf_
  - [x] 5.2 Crear `infra/bootstrap/variables.tf` con todas las variables definidas en la sección 2.3 del diseño: `state_bucket_name`, `devops_account_id`, `networking_account_id`, `workload_dev_account_id`, `workload_pre_account_id`, `workload_prod_account_id`, `dr_account_id` (regex `^[0-9]{12}$`), `github_org`, `github_repo` (validación no vacía), `create_github_oidc_provider` (bool, default `true`), `allowed_principals` (list(string), validación `length >= 1`), `break_glass_role_arn` (regex `^arn:aws:iam::`), `bootstrap_operator_arn` (regex `^arn:aws:iam::[0-9]{12}:(role|user)/`), `enable_vpn` (bool, default `false`), `project`, `environment`, `owner`, `cost_center`, `data_classification` (todos string, validación no vacía ni solo espacios)
    - _Requirements: 2.7, 4.5, 5.5, 12.2_
    - _Design: Componente 2.3 — Variables de bootstrap_
  - **Verificación:** `terraform validate` en `infra/bootstrap/` termina con código de salida 0 (puede requerir un `providers.tf` mínimo para que el directorio sea válido; crear junto con la tarea 6).

- [x] 6. Bootstrap — `providers.tf`
  - Crear `infra/bootstrap/providers.tf` con el provider por defecto (`region = "eu-west-1"`, bloque `default_tags { tags = local.default_tags }`) y cinco providers con alias: `networking`, `workload_dev`, `workload_pre`, `workload_prod` (todos `region = "eu-west-1"`) y `dr` (`region = "eu-central-1"`); cada uno con `assume_role { role_arn = "arn:aws:iam::<account_id_var>:role/OrganizationAccountAccessRole" }` y `default_tags`
  - Declarar `local.default_tags` (mapa con `Project`, `Environment`, `Owner`, `CostCenter`, `ManagedBy = "terraform"`, `DataClassification` construido desde las variables de etiquetado) en un bloque `locals` del mismo archivo o en `main.tf`
  - _Requirements: 5.7, 12.1_
  - _Design: Componente 2.4 — Providers con alias_
  - **Verificación:** `terraform validate` en `infra/bootstrap/` termina con código de salida 0 y sin errores.

- [x] 7. Bootstrap — `iam_policies.tf`
  - Crear `infra/bootstrap/iam_policies.tf` con un bloque `locals` que contenga:
    - `state_bucket_arn`, `github_plan_role_arn`, `github_apply_role_arn` construidos mediante interpolación de variables (no atributos de recursos)
    - `chatbot_plan_role_arns` y `chatbot_deploy_role_arns` construidos con expresión `for` sobre `local.target_accounts`
    - `github_plan_policy_json`: JSON con `jsonencode` que otorga `s3:GetObject` + `s3:ListBucket` sobre el bucket de estado, `s3:PutObject` + `s3:DeleteObject` sobre objetos `.tflock`, `kms:Decrypt`, `kms:Encrypt` y `kms:GenerateDataKey` sobre `Resource = "arn:aws:kms:eu-west-1:${var.devops_account_id}:key/*"` con `Condition = { "ForAnyValue:StringEquals": { "kms:ResourceAliases": ["alias/chatbot-devops-tfstate"] } }`, y `sts:AssumeRole` sobre `chatbot_plan_role_arns`
    - `github_apply_policy_json`: JSON con `jsonencode` que otorga `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` y `s3:ListBucket` sobre el bucket de estado; `s3:PutObject` y `s3:DeleteObject` sobre objetos `.tflock`; `kms:Decrypt`, `kms:Encrypt` y `kms:GenerateDataKey` con el mismo Resource wildcard y condición `kms:ResourceAliases` que en `github_plan_policy_json`; `sts:AssumeRole` sobre `chatbot_deploy_role_arns`; y permisos de ECR de la cuenta DevOps (`ecr:GetAuthorizationToken`, `ecr:BatchGetImage`, `ecr:PutImage`, `ecr:CreateRepository`, etc.). **Sin** acciones `iam:*`, **sin** acciones de gestión de KMS (`kms:Create*`, `kms:Delete*`, `kms:Put*`), **sin** acciones de servicios workload.
    - `bucket_policy_json`: JSON con `jsonencode` con dos bloques `Deny` — Bloque 1: `aws:SecureTransport = false`; Bloque 2: `aws:PrincipalArn NotLike` con lista que incluye `github_plan_role_arn`, `github_apply_role_arn`, `var.break_glass_role_arn`, `var.bootstrap_operator_arn` y `var.allowed_principals`
  - Ningún ARN en los locals debe referenciar atributos de recursos (`aws_s3_bucket.tfstate.arn`, etc.); todos se construyen desde variables
  - _Requirements: 2.5, 2.7, 4.3, 4.4_
  - _Design: Componente 2.1 — iam_policies.tf; Componente 2.2 — Roles GitHub; Componente 2.5 — Política del bucket_
  - **Verificación:** `terraform validate` en `infra/bootstrap/` termina con código de salida 0 y sin errores.

- [~] 8. Bootstrap — `main.tf` (KMS, S3, OIDC)
  - Crear `infra/bootstrap/main.tf` con:
    - `local.target_accounts` (mapa con `account_id` y `region` de las cinco cuentas destino)
    - Recurso `aws_kms_key.state` (`enable_key_rotation = true`, `deletion_window_in_days = 10`, etiquetas desde `local.default_tags`)
    - Recurso `aws_kms_alias.state` (`name = "alias/chatbot-devops-tfstate"`)
    - Recurso `aws_s3_bucket.tfstate` (`bucket = var.state_bucket_name`)
    - Recurso `aws_s3_bucket_versioning.tfstate` (`status = "Enabled"`)
    - Recurso `aws_s3_bucket_server_side_encryption_configuration.tfstate` (SSE-KMS apuntando a `aws_kms_key.state.arn`)
    - Recurso `aws_s3_bucket_public_access_block.tfstate` (los cuatro atributos en `true`)
    - Recurso `aws_s3_bucket_lifecycle_configuration.tfstate`: regla que expire versiones no actuales (`noncurrent_version_expiration`) a los 90 días; corrige el check de checkov `CKV2_AWS_61` (ausencia de lifecycle en el bucket de estado)
    - Recurso `aws_s3_bucket_policy.tfstate` (`policy = local.bucket_policy_json`)
    - Recurso `aws_iam_openid_connect_provider.github` (`count = var.create_github_oidc_provider ? 1 : 0`, `url = "https://token.actions.githubusercontent.com"`, `client_id_list = ["sts.amazonaws.com"]`; sin `thumbprint_list`)
    - `data "aws_iam_openid_connect_provider" "github"` (`count = var.create_github_oidc_provider ? 0 : 1`, ARN construido desde `var.devops_account_id`)
    - `local.github_oidc_arn` que unifica ambas ramas `count`
    - Argumento `policy` en `aws_kms_key.state`: política KMS explícita con dos sentencias — (1) `kms:*` para el principal `arn:aws:iam::${var.devops_account_id}:root` (administración por la raíz de la cuenta); (2) `kms:Decrypt`, `kms:Encrypt`, `kms:GenerateDataKey` y `kms:DescribeKey` para los principals `local.github_plan_role_arn`, `local.github_apply_role_arn`, `var.bootstrap_operator_arn` y `var.break_glass_role_arn` (todos construidos desde variables, sin referenciar atributos de `aws_iam_role.*`, para evitar dependencia circular y mantener los ARN conocidos en plan); corrige el check de checkov `CKV2_AWS_64` (política de clave sin sentencias de uso restringido)
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.4_
  - _Design: Componente 2.2 — KMS, S3, IAM OIDC_
  - **Verificación:** `terraform validate` en `infra/bootstrap/` termina con código de salida 0 y sin errores.

- [~] 9. Bootstrap — roles IAM de GitHub Actions
  - Añadir a `infra/bootstrap/main.tf` (o en `iam_roles.tf` si se prefiere separar) los recursos:
    - `aws_iam_role.github_plan`: trust policy con `sts:AssumeRoleWithWebIdentity` desde `local.github_oidc_arn`; condición `StringLike` sobre `token.actions.githubusercontent.com:sub` aceptando `repo:<org>/<repo>:pull_request` y `repo:<org>/<repo>:ref:refs/heads/main`
    - `aws_iam_role.github_apply`: trust policy análoga; condición `StringLike` aceptando `repo:<org>/<repo>:ref:refs/heads/main` y `repo:<org>/<repo>:environment:*`
    - `aws_iam_policy.github_plan` con `policy = local.github_plan_policy_json`
    - `aws_iam_policy.github_apply` con `policy = local.github_apply_policy_json`
    - `aws_iam_role_policy_attachment.github_plan` adjuntando la política al rol
    - `aws_iam_role_policy_attachment.github_apply` adjuntando la política al rol
  - Verificar que las trust policies referencian `local.github_oidc_arn` (no valores hardcodeados) y que el campo `Principal.Federated` toma el ARN del OIDC provider, no el de los roles
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.6_
  - _Design: Componente 2.2 — Roles GitHub Actions_
  - **Verificación:** `terraform validate` en `infra/bootstrap/` termina con código de salida 0 y sin errores.

- [ ] 10. Bootstrap — módulo hijo `target-roles` y cinco invocaciones
  - [~] 10.1 Crear `infra/bootstrap/modules/target-roles/versions.tf` con `required_version = ">= 1.10"` y el provider `hashicorp/aws ~> 6.73`
    - _Requirements: 5.7_
    - _Design: Componente 2.2 — Roles destino_
  - [~] 10.2 Crear `infra/bootstrap/modules/target-roles/variables.tf` con las variables `github_plan_arn` (string), `github_apply_arn` (string), `account_name` (string) y `enable_vpn` (bool, default `false`); todas con `description` y `type`
    - _Requirements: 5.5, 5.6_
    - _Design: Componente 2.2 — Roles destino_
  - [~] 10.3 Crear `infra/bootstrap/modules/target-roles/main.tf` con:
    - `aws_iam_role.chatbot_plan`: trust policy con `sts:AssumeRole` desde `var.github_plan_arn` sin comodines
    - `aws_iam_role.chatbot_deploy`: trust policy con `sts:AssumeRole` desde `var.github_apply_arn` sin comodines
    - `aws_iam_role_policy_attachment.plan_readonly`: adjunta `arn:aws:iam::aws:policy/ReadOnlyAccess` a `chatbot_plan`
    - `aws_iam_policy.deploy_base`: política placeholder (permiso mínimo temporal; se amplía en specs posteriores)
    - _Requirements: 5.1, 5.2, 5.3, 5.4_
    - _Design: Componente 2.2 — Roles destino; módulo hijo_
  - [~] 10.4 Añadir a `infra/bootstrap/main.tf` los cinco bloques `module` explícitos (`target_roles_networking`, `target_roles_workload_dev`, `target_roles_workload_pre`, `target_roles_workload_prod`, `target_roles_dr`) con `source = "./modules/target-roles"`, las tres variables de entrada y `providers = { aws = aws.<alias> }` usando la referencia literal de cada alias
    - _Requirements: 5.1, 5.2, 5.7_
    - _Design: Componente 2.2 — cinco bloques module explícitos_
  - **Verificación:** `terraform validate` en `infra/bootstrap/` termina con código de salida 0 y sin errores.

- [~] 11. Bootstrap — `outputs.tf`, `backend.tf` y `README.md`
  - Crear `infra/bootstrap/outputs.tf` con los outputs definidos en la sección Data Models del diseño: `state_bucket_name`, `state_bucket_arn`, `state_kms_key_arn`, `github_plan_role_arn`, `github_apply_role_arn`, `chatbot_plan_role_arns` (mapa `cuenta → ARN`), `chatbot_deploy_role_arns` (mapa `cuenta → ARN`)
  - Crear `infra/bootstrap/backend.tf` con `backend "local" {}` (estado local inicial; se reemplaza manualmente antes de `terraform init -migrate-state`)
  - Crear `infra/bootstrap/README.md` con las secciones: Prerequisites, Uso inicial (pasos 1–3), Migración del estado a S3 (pasos 4–6 del diseño con el bloque backend S3 exacto y el comando `terraform init -migrate-state`), y Desbloqueo de lock huérfano
  - _Requirements: 2.8, 2.9, 11.1_
  - _Design: Componente 2.1 — backend.tf y outputs.tf; Componente 2.6 — Flujo de bootstrapping_
  - **Verificación:** `terraform validate` en `infra/bootstrap/` termina con código de salida 0 y sin errores; el archivo `README.md` contiene las instrucciones de migración con el bloque backend S3 de ejemplo.

- [~] 12. Test de bootstrap
  - Crear `infra/bootstrap/tests/bootstrap_test.tftest.hcl` con:
    - Seis declaraciones `mock_provider "aws" {}` al nivel raíz: una sin alias y cinco con `alias =` ("networking", "workload_dev", "workload_pre", "workload_prod", "dr")
    - Bloque `variables {}` con los 17 inputs de la sección 2.3 usando valores ficticios (`devops_account_id = "111111111111"`, etc.)
    - Bloque `run "p_iam_01_plan_role_no_write_actions"` (`command = plan`): assert que verifica P-IAM-01 con el patrón `flatten([tolist(try(tolist(stmt.Action), [stmt.Action]))])` sobre `jsondecode(local.github_plan_policy_json)`
    - Bloque `run "p_iam_02_apply_role_no_workload_perms"` (`command = plan`): assert que verifica P-IAM-02 comprobando que ninguna acción empieza por `ec2:`, `ecs:`, `rds:`, `elasticloadbalancing:`, `route53:`, `bedrock:`, `dynamodb:` o `iam:`
    - Bloque `run "p_iam_03_plan_role_assumes_only_plan_roles"` (`command = plan`): assert que verifica P-IAM-03 — todo `sts:AssumeRole` en `github_plan_policy_json` apunta solo a ARNs que terminan en `:role/chatbot-plan-role`
    - Bloque `run "p_iam_04_apply_role_assumes_only_deploy_roles"` (`command = plan`): assert análogo para P-IAM-04 sobre `github_apply_policy_json` y `:role/chatbot-deploy-role`
    - Bloque `run "p_s3_02_tls_enforced"` (`command = plan`): assert que verifica P-S3-02 — existe un `Deny` en `bucket_policy_json` con `Condition.Bool["aws:SecureTransport"] == "false"`
  - _Requirements: 2, 4, 5_
  - _Design: Componente 2.7 — Test del bootstrap; Correctness Properties P-IAM-01..04 y P-S3-02_
  - **Verificación:** `terraform test` ejecutado en `infra/bootstrap/` completa los cinco bloques `run` con estado `pass` y código de salida 0, sin credenciales AWS en el entorno.

- [~] 13. Checkpoint — validación integral del código Terraform
  - Ejecutar `terraform init -backend=false` en `infra/modules/kms/` y luego `terraform validate`; confirmar código de salida 0
  - Ejecutar `terraform test` en `infra/modules/kms/`; confirmar que los dos bloques `run` (`valid_key` e `invalid_window`) pasan con estado `pass`
  - Ejecutar `terraform init -backend=false` en `infra/bootstrap/` y luego `terraform validate`; confirmar código de salida 0
  - Ejecutar `terraform test` en `infra/bootstrap/`; confirmar que los cinco bloques `run` (P-IAM-01..04 y P-S3-02) pasan con estado `pass`
  - Ejecutar `terraform fmt -check -recursive infra/`; confirmar que no hay archivos con formato incorrecto (código de salida 0)
  - Ejecutar `tflint --init && tflint --recursive` desde la raíz del repositorio; resolver todos los warnings y errores
  - Ejecutar `checkov -d infra/ --config-file .checkov.yaml`; si falla en `infra/modules/kms/` por **CKV2_AWS_64** (política de CMK sin sentencias de uso), añadir `CKV2_AWS_64` a la sección `skip-check:` de `.checkov.yaml` con el comentario: `# CKV2_AWS_64: módulo reutilizable; la política de la clave la aporta el llamador mediante var.policy`. Si falla en cualquier otro check no justificado, corregir el recurso antes de continuar
  - Resolver cualquier error antes de continuar con los ADRs
  - **Verificación:** `terraform validate` en `infra/modules/kms/` y `infra/bootstrap/` terminan con código de salida 0; `terraform test` en ambos directorios completa todos los `run` con estado `pass`; `terraform fmt -check -recursive infra/` termina con código de salida 0; `tflint --recursive` no reporta errores; `checkov` termina con código de salida 0 (todos los checks pasan o están justificados en `skip-check:`).

- [~] 14. ADR-001 — Estructura del repositorio y herramientas Terraform
  - Crear `docs/adr/ADR-001-terraform-estructura-repositorio.md` con las secciones definidas en el diseño: Contexto, Opciones evaluadas, Decisión y Consecuencias
  - La sección Contexto debe mencionar los requisitos del proyecto (multicuenta, CI/CD sin secretos, prueba técnica evaluable)
  - La sección Opciones evaluadas debe comparar: (A) Terraform monolítico cuenta única, (B) módulos + composición en `live/` con `provider assume_role`, (C) Terragrunt; con al menos una ventaja y una limitación por opción
  - La sección Decisión debe indicar la opción B y justificar con blast radius reducido y permisos mínimos diferenciados por rol
  - La sección Consecuencias debe incluir la justificación de `tflint` frente a Trivy y Terrascan, y de `checkov` (cobertura, SARIF, análisis de grafo); mencionar que `terraform plan` sobre `infra/bootstrap/` se ejecuta manualmente
  - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_
  - _Design: Componente — ADR-001_
  - **Verificación:** el archivo existe en la ruta `docs/adr/ADR-001-terraform-estructura-repositorio.md`; contiene las cuatro secciones con contenido sustantivo; menciona explícitamente `use_lockfile = true`, estructura multicuenta, `tflint` y `checkov`.

- [~] 15. ADR-002 — Bloqueo de estado con `use_lockfile`
  - Crear `docs/adr/ADR-002-bloqueo-estado-use-lockfile.md` con las secciones: Contexto, Opciones evaluadas, Decisión y Consecuencias
  - La sección Contexto debe describir el problema del locking de estado concurrente y la historia de Terraform hasta 1.10/1.11
  - La sección Opciones evaluadas debe incluir la tabla comparativa con las cuatro columnas del requisito 10.3: coste estimado, recursos AWS adicionales, procedimiento de desbloqueo, estado de soporte (`dynamodb_table` deprecado en Terraform 1.11)
  - La sección Decisión debe indicar `use_lockfile = true` y mencionar que almacena el objeto `.tflock` en el mismo bucket S3
  - La sección Consecuencias debe incluir las tres ventajas (coste cero de locking, eliminación de DynamoDB, soporte nativo desde 1.10) y la subsección de riesgos con el escenario de lock huérfano y el procedimiento de desbloqueo (`terraform force-unlock <LOCK_ID>` o `aws s3 rm *.tflock`)
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_
  - _Design: Componente — ADR-002_
  - **Verificación:** el archivo existe en `docs/adr/ADR-002-bloqueo-estado-use-lockfile.md`; contiene la tabla comparativa con las cuatro columnas; menciona explícitamente `use_lockfile = true`, Terraform 1.11, lock huérfano y `terraform force-unlock`.

---

## Notes

- Ninguna tarea requiere `terraform apply` ni credenciales AWS reales para ser marcada como completada.
- Las tareas 5–11 son interdependientes: `terraform validate` en `infra/bootstrap/` requiere que el directorio contenga `versions.tf`, `providers.tf` y al menos un `main.tf` mínimo para ser válido. Se recomienda ejecutar la validación incremental después de completar la tarea 6 y luego después de cada tarea subsiguiente.
- El archivo `.terraform.lock.hcl` generado por `terraform init` debe commitearse (no está en `.gitignore`).
- El recurso `aws_iam_openid_connect_provider` en `hashicorp/aws ~> 6.73` no requiere el argumento `thumbprint_list` para GitHub Actions; omitirlo es el comportamiento correcto.
- Los `locals` de `iam_policies.tf` deben construirse exclusivamente desde variables (no desde atributos de recursos) para ser evaluables en plan durante `terraform test` con `mock_provider`.
- El campo `providers` de los bloques `module` en `main.tf` requiere referencias literales (`providers = { aws = aws.networking }`); no se puede iterar dinámicamente.
- Los ADRs (tareas 14–15) están en español; el código Terraform y los comentarios técnicos en inglés.
- Consultar el MCP de Terraform para confirmar los argumentos exactos de cada recurso antes de escribirlos.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1"] },
    { "id": 1, "tasks": ["2", "3.1"] },
    { "id": 2, "tasks": ["3.2", "3.3"] },
    { "id": 3, "tasks": ["3.4", "3.5"] },
    { "id": 4, "tasks": ["4.1"] },
    { "id": 5, "tasks": ["4.2"] },
    { "id": 6, "tasks": ["5.1", "5.2"] },
    { "id": 7, "tasks": ["6"] },
    { "id": 8, "tasks": ["7"] },
    { "id": 9, "tasks": ["8"] },
    { "id": 10, "tasks": ["9", "10.1", "10.2"] },
    { "id": 11, "tasks": ["10.3"] },
    { "id": 12, "tasks": ["10.4"] },
    { "id": 13, "tasks": ["11"] },
    { "id": 14, "tasks": ["12"] },
    { "id": 15, "tasks": ["13"] },
    { "id": 16, "tasks": ["14", "15"] }
  ]
}
```
