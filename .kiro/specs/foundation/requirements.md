# Requirements Document

## Introduction

El spec **foundation** cubre la preparación del repositorio de infraestructura para la plataforma del agente conversacional en AWS (prueba técnica SDG Group). Su objetivo es establecer los cimientos sobre los que todos los specs posteriores construirán: estructura de directorios, código Terraform de bootstrap (bucket de estado, roles OIDC de GitHub, roles de despliegue multicuenta), herramientas de calidad de código, el módulo `kms` como patrón de referencia para módulos reutilizables, y los ADRs que justifican las decisiones de diseño relevantes.

Todo el código producido debe poder validarse **sin credenciales AWS reales** (`terraform validate` y `terraform test` con `mock_provider`), ya que se trata de una prueba técnica que no se desplegará en producción.

---

## Glossary

- **Bootstrap**: conjunto de recursos Terraform que se aplican una sola vez, en local, con credenciales de administrador de la cuenta DevOps, antes de que el pipeline CI/CD pueda funcionar.
- **Backend S3**: mecanismo de almacenamiento remoto del estado de Terraform en un bucket S3 con `use_lockfile = true`.
- **Bootstrap_local**: estado local de Terraform (`backend "local" {}`) con el que arranca `infra/bootstrap/` antes de que el bucket S3 de estado exista.
- **Break-glass role**: rol IAM de emergencia cuyo ARN se incluye obligatoriamente en `allowed_principals` del bucket de estado, para garantizar que siempre existe una vía de acceso al estado incluso si el pipeline falla.
- **CMK** (Customer Managed Key): clave KMS gestionada por el cliente, con rotación anual activada.
- **OIDC Provider**: proveedor de identidad OpenID Connect registrado en IAM que permite a GitHub Actions asumir roles de AWS sin secretos estáticos.
- **Rol de despliegue**: par de roles IAM en cada cuenta destino (`chatbot-plan-role` y `chatbot-deploy-role`) que los roles de GitHub asumen mediante `sts:AssumeRole` para realizar operaciones Terraform con mínimo privilegio diferenciado por operación.
- **Módulo reutilizable**: carpeta dentro de `infra/modules/` con la estructura estándar (main.tf, variables.tf, outputs.tf, versions.tf, README.md, tests/).
- **Mock provider**: mecanismo de `terraform test` que simula respuestas de la API de AWS, permitiendo ejecutar pruebas sin credenciales reales.
- **ADR** (Architecture Decision Record): documento que registra contexto, opciones evaluadas, decisión tomada y consecuencias.
- **Terraform_CLI**: herramienta de línea de comandos de HashiCorp Terraform versión >= 1.10.
- **Sistema_CI**: pipeline de GitHub Actions que ejecuta comprobaciones de calidad en cada pull request y aplica cambios en la rama `main`.
- **Módulo_KMS**: módulo Terraform reutilizable ubicado en `infra/modules/kms/` que encapsula la creación de CMKs.
- **Repo**: repositorio Git del proyecto, alojado en GitHub.
- **Cuenta_DevOps**: cuenta AWS dedicada a herramientas compartidas (ECR, estado Terraform, roles OIDC).
- **pre-commit**: herramienta de hooks Git que ejecuta comprobaciones automáticas antes de cada commit.

---

## Requirements

### Requisito 1: Estructura de directorios del repositorio

**User Story:** Como ingeniero de infraestructura, quiero que el repositorio tenga la estructura de carpetas definida en `structure.md`, para que todos los módulos y entornos sigan una organización predecible y los pipelines CI/CD puedan ubicar los archivos por convención.

#### Criterios de aceptación

1. THE **Repo** SHALL contener las carpetas `.github/workflows/`, `docs/arquitectura/`, `docs/adr/`, `docs/costes/`, `docs/inventario/`, `infra/bootstrap/`, `infra/modules/`, `infra/live/networking/eu-west-1/`, `infra/live/devops/eu-west-1/`, `infra/live/workload/dev/`, `infra/live/workload/pre/`, `infra/live/workload/prod/`, `infra/live/dr/eu-central-1/` y `tests/`.
2. WHEN una carpeta no contiene archivos con extensión `.tf`, `.tfvars`, `.tftest.hcl` o `.md`, THE **Repo** SHALL incluir un archivo `.gitkeep` en esa carpeta para preservarla en el historial Git.
3. THE **Repo** SHALL incluir un archivo `.gitignore` en la raíz que contenga al menos las siguientes entradas: `.terraform/`, `*.tfstate`, `*.tfstate.backup`, `crash.log`, `*.auto.tfvars`, `override.tf` y `override.tf.json`; el archivo SHALL conservar también cualquier entrada preexistente en el repositorio (por ejemplo, `.DS_Store`).
4. THE **Repo** SHALL incluir, dentro de `infra/modules/`, una subcarpeta por cada módulo definido en `structure.md`: `tgw-hub`, `egress-inspection`, `central-endpoints`, `dns`, `workload-vpc`, `alb-oidc`, `ecs-platform`, `ecs-service`, `privatelink-service`, `aurora-pgvector`, `dynamodb-tracker`, `bedrock-kb`, `documents-bucket`, `ecr`, `kms`, `powerbi-gateway`, `observability` y `budgets`.
5. WHEN se ejecuta `git status` en un clon limpio del repositorio, THE **Git_CLI** SHALL reportar cero archivos con estado `untracked` en cualquier carpeta listada en los criterios 1 y 4.

> *Traza a product.md*: requisito no funcional de "servicios gestionados y de bajo mantenimiento" (convención clara reduce fricción de incorporación).

---

### Requisito 2: Bootstrap – bucket S3 de estado Terraform

**User Story:** Como operador de plataforma, quiero un bucket S3 seguro para almacenar el estado de Terraform de todas las carpetas `live/`, para que el estado sea compartido entre miembros del equipo y esté protegido frente a pérdida o acceso no autorizado.

#### Criterios de aceptación

1. EL **código de `infra/bootstrap/`** SHALL crear el bucket S3 de estado mediante el recurso `aws_s3_bucket` del provider `hashicorp/aws` versión `~> 6.73`.
2. EL **código de `infra/bootstrap/`** SHALL habilitar versionado en el bucket mediante el recurso `aws_s3_bucket_versioning` con `versioning_configuration { status = "Enabled" }`.
3. EL **código de `infra/bootstrap/`** SHALL cifrar el bucket con SSE-KMS mediante el recurso `aws_s3_bucket_server_side_encryption_configuration` apuntando a la CMK creada en el mismo módulo `infra/bootstrap/` para la cuenta DevOps.
4. EL **código de `infra/bootstrap/`** SHALL bloquear todo acceso público al bucket mediante el recurso `aws_s3_bucket_public_access_block` con los cuatro atributos (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`) establecidos en `true`.
5. IF una solicitud al bucket tiene el atributo `aws:SecureTransport` igual a `false`, THEN EL **código de `infra/bootstrap/`** SHALL denegar la operación mediante una condición `aws:SecureTransport = false` en un bloque `Deny` de la política de bucket que cubra la acción `s3:*` para todos los principals.
6. THE **Terraform_CLI** SHALL configurar el backend S3 usando `use_lockfile = true` como único mecanismo de locking; la configuración del backend no declarará ningún recurso `aws_dynamodb_table` para este propósito.
7. THE **código de `infra/bootstrap/`** SHALL restringir las operaciones sobre el bucket mediante un bloque `Deny` con condición `aws:PrincipalArn NotLike` en la política de bucket, permitiendo únicamente los principals listados en la variable `allowed_principals`; esta variable SHALL incluir obligatoriamente al menos un ARN de rol de emergencia (`break_glass_role_arn`) para prevenir el bloqueo total del bucket en caso de fallo del pipeline.
8. WHEN se ejecuta `terraform validate` en `infra/bootstrap/`, THE **Terraform_CLI** SHALL completar la validación sin errores.
9. THE **código de `infra/bootstrap/`** SHALL iniciarse con `backend "local" {}` y SHALL incluir en `infra/bootstrap/README.md` los pasos para migrar el estado al backend S3 una vez creado el bucket, usando `terraform init -migrate-state`.

> *Traza a product.md*: "cifrado en reposo y en tránsito"; "servicios gestionados y de bajo mantenimiento".

---

### Requisito 3: Bootstrap – proveedor OIDC de GitHub en la cuenta DevOps

**User Story:** Como ingeniero de seguridad, quiero un proveedor OIDC de GitHub registrado en la cuenta DevOps, para que los workflows de GitHub Actions puedan obtener credenciales AWS temporales sin almacenar secretos estáticos en el repositorio.

#### Criterios de aceptación

1. EL **código de `infra/bootstrap/`** SHALL crear el proveedor OIDC mediante el recurso `aws_iam_openid_connect_provider` con `url = "https://token.actions.githubusercontent.com"` y `client_id_list = ["sts.amazonaws.com"]`.
2. EL **código de `infra/bootstrap/`** SHALL omitir el argumento `thumbprint_list` en el proveedor OIDC de GitHub, ya que AWS valida este proveedor mediante su propia biblioteca de CAs de confianza (comportamiento documentado en el provider `hashicorp/aws` >= 5.x).
3. WHEN se ejecuta `terraform validate` en `infra/bootstrap/`, THE **Terraform_CLI** SHALL completar la validación sin errores en el recurso `aws_iam_openid_connect_provider`.
4. THE **código de `infra/bootstrap/`** SHALL declarar una variable booleana `create_github_oidc_provider` (por defecto `true`). WHEN `create_github_oidc_provider` sea `true`, SHALL crear el recurso `aws_iam_openid_connect_provider`. WHEN `create_github_oidc_provider` sea `false`, SHALL usar un `data "aws_iam_openid_connect_provider"` para referenciar el proveedor ya existente por su ARN, construido como `arn:aws:iam::<account_id>:oidc-provider/token.actions.githubusercontent.com`.
5. WHEN se crea el proveedor OIDC, EL **código de `infra/bootstrap/`** SHALL adjuntar las etiquetas obligatorias `Project`, `Environment`, `Owner`, `CostCenter`, `ManagedBy=terraform` y `DataClassification` al recurso `aws_iam_openid_connect_provider`.

> *Traza a product.md*: requisito no funcional implícito de seguridad (sin secretos estáticos en GitHub).

---

### Requisito 4: Bootstrap – roles IAM de GitHub Actions

**User Story:** Como ingeniero de CI/CD, quiero roles IAM específicos para los workflows de plan y apply de Terraform, para que los permisos sean mínimos y estén diferenciados según la operación que realiza el pipeline.

#### Criterios de aceptación

1. WHEN se ejecuta `terraform apply` en `infra/bootstrap/`, EL **código de `infra/bootstrap/`** SHALL crear el rol `github-terraform-plan` mediante `aws_iam_role` con una política de confianza que permita `sts:AssumeRoleWithWebIdentity` desde el proveedor OIDC de GitHub (`token.actions.githubusercontent.com`), con la condición `StringEquals` sobre `token.actions.githubusercontent.com:sub` igual a `repo:<org>/<repo>:pull_request`, en la cuenta DevOps.
2. WHEN se ejecuta `terraform apply` en `infra/bootstrap/`, EL **código de `infra/bootstrap/`** SHALL crear el rol `github-terraform-apply` mediante `aws_iam_role` con una política de confianza que permita `sts:AssumeRoleWithWebIdentity` desde el proveedor OIDC de GitHub, con la condición `StringLike` sobre `token.actions.githubusercontent.com:sub` que coincida con `repo:<org>/<repo>:ref:refs/heads/main` o `repo:<org>/<repo>:environment:*`, en la cuenta DevOps.
3. WHEN se ejecuta `terraform apply` en `infra/bootstrap/`, EL **código de `infra/bootstrap/`** SHALL adjuntar al rol `github-terraform-plan` una política IAM con exactamente los siguientes permisos: `s3:GetObject` y `s3:ListBucket` sobre el ARN del bucket de estado Terraform; `s3:PutObject` y `s3:DeleteObject` sobre los objetos con sufijo `.tflock` en ese mismo bucket (necesario porque `use_lockfile` adquiere el lock también durante `terraform plan`); `kms:Decrypt`, `kms:Encrypt` y `kms:GenerateDataKey` sobre el ARN de la CMK del estado; y `sts:AssumeRole` exclusivamente sobre los ARNs de los roles `chatbot-plan-role` de las cuentas destino. La condición `StringLike` sobre `token.actions.githubusercontent.com:sub` SHALL aceptar tanto `repo:<org>/<repo>:pull_request` como `repo:<org>/<repo>:ref:refs/heads/main` para soportar el workflow de drift.
4. WHEN se ejecuta `terraform apply` en `infra/bootstrap/`, EL **código de `infra/bootstrap/`** SHALL adjuntar al rol `github-terraform-apply` una política IAM limitada a: `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` y `s3:ListBucket` sobre el ARN del bucket de estado; `s3:PutObject` y `s3:DeleteObject` sobre los objetos `.tflock` del bucket; `kms:Decrypt`, `kms:Encrypt` y `kms:GenerateDataKey` sobre la CMK del estado; `sts:AssumeRole` exclusivamente sobre los ARNs de los roles `chatbot-deploy-role` de las cuentas destino; y los permisos de creación y actualización de recursos propios de la cuenta DevOps (ECR, KMS, IAM para roles OIDC). La condición sobre `token.actions.githubusercontent.com:sub` SHALL usar `StringLike` aceptando `repo:<org>/<repo>:ref:refs/heads/main` y `repo:<org>/<repo>:environment:*`. Los permisos de los servicios de las cuentas workload (EC2, ECS, RDS, etc.) van en `chatbot-deploy-role`, no en este rol. La condición de scoping de recursos SHALL usar `aws:RequestTag/ManagedBy` (en creación) en lugar de `aws:ResourceTag/ManagedBy`. Las acciones NO están limitadas a una región específica; se aplican a `eu-west-1` y `eu-central-1`.
5. WHERE las variables `github_org` o `github_repo` no estén definidas o sean cadenas vacías, THE **Terraform_CLI** SHALL producir un error de validación con un mensaje que identifique el nombre de la variable faltante y detenga la ejecución antes de realizar cualquier llamada a la API de AWS.
6. WHEN se ejecuta `terraform validate` en `infra/bootstrap/`, THE **Terraform_CLI** SHALL completar la validación sin errores en los recursos `aws_iam_role`.

> *Traza a product.md*: "nada de IAM users ni claves estáticas. Mínimo privilegio" (definido en tech.md).

---

### Requisito 5: Bootstrap – roles de despliegue en cuentas destino

**User Story:** Como operador multicuenta, quiero dos roles de despliegue en cada cuenta destino (`chatbot-plan-role` y `chatbot-deploy-role`), para que el principio de mínimo privilegio se aplique también en las cuentas workload y el rol de plan no pueda nunca escribir recursos.

#### Criterios de aceptación

1. EL **código de `infra/bootstrap/`** SHALL crear el rol `chatbot-plan-role` en cada una de las cuentas Networking, Workload-Dev, Workload-Pre, Workload-Prod y DR mediante `aws_iam_role` con una política de confianza que permita `sts:AssumeRole` exclusivamente desde el ARN exacto del rol `github-terraform-plan` de la cuenta DevOps, sin comodines en el `Principal`.
2. EL **código de `infra/bootstrap/`** SHALL crear el rol `chatbot-deploy-role` en cada una de las cuentas Networking, Workload-Dev, Workload-Pre, Workload-Prod y DR mediante `aws_iam_role` con una política de confianza que permita `sts:AssumeRole` exclusivamente desde el ARN exacto del rol `github-terraform-apply` de la cuenta DevOps, sin comodines en el `Principal`.
3. THE **código de `infra/bootstrap/`** SHALL adjuntar al `chatbot-plan-role` la política AWS gestionada `ReadOnlyAccess` más permisos de lectura del estado S3 (`s3:GetObject`, `s3:ListBucket`) y operaciones sobre objetos `.tflock` (`s3:PutObject`, `s3:DeleteObject`) sobre el bucket de estado, y `kms:Decrypt` sobre la CMK del estado.
4. THE **código de `infra/bootstrap/`** SHALL adjuntar al `chatbot-deploy-role` los permisos de escritura necesarios para los recursos Terraform del alcance de cada cuenta, aplicando mínimo privilegio; los permisos específicos de cada cuenta se ampliarán en los specs de networking, workload-platform y operations-dr.
5. THE **código de `infra/bootstrap/`** SHALL parametrizar los IDs de las cinco cuentas destino como variables de tipo `string` con validación de formato `^[0-9]{12}$`; ningún ID de cuenta SHALL aparecer hardcodeado en el código.
6. WHERE la variable `enable_vpn` sea `false`, THE **código de `infra/bootstrap/`** SHALL omitir cualquier permiso relacionado con `ec2:CreateVpnConnection`, `ec2:CreateCustomerGateway` y `ec2:CreateVpnGateway` en las políticas adjuntas a `chatbot-deploy-role`.
7. THE **código de `infra/bootstrap/`** SHALL crear los roles de las cuentas destino usando providers con alias que asumen `OrganizationAccountAccessRole` en cada cuenta mediante `assume_role { role_arn = "arn:aws:iam::<account_id>:role/OrganizationAccountAccessRole" }`.
8. WHEN se ejecuta `terraform validate` en `infra/bootstrap/`, THE **Terraform_CLI** SHALL completar sin errores para todos los recursos de roles de despliegue.

> *Traza a product.md*: "multicuenta con provider assume_role (rol de despliegue por cuenta); nada de credenciales en código" (definido en structure.md). Mínimo privilegio diferenciado plan/apply.

---

### Requisito 6: Configuración de calidad de código

**User Story:** Como contribuidor al repositorio, quiero herramientas de calidad configuradas y ejecutables localmente y en CI, para que los problemas de formato, seguridad y documentación se detecten antes de que el código llegue a la rama principal.

#### Criterios de aceptación

1. THE **Repo** SHALL contener un archivo `.tflint.hcl` en la raíz que declare el plugin oficial de AWS con versión fijada (`source = "github.com/terraform-linters/tflint-ruleset-aws"`, campo `version` explícito), active `ruleset = "aws"`, y habilite al menos las reglas `terraform_naming_convention` y `terraform_typed_variables`.
2. THE **Repo** SHALL contener un archivo `.checkov.yaml` en la raíz que establezca `directory: infra/` y `output-file-type: sarif`; el archivo NO SHALL incluir filtro de severidad (`check:` por nivel), ya que checkov en modo CLI sin API key de Prisma Cloud ejecuta todos los checks disponibles por defecto; la sección `skip-check:` SHALL listar los identificadores `CKV_AWS_*` que se omiten, con un comentario en la misma línea que justifique cada excepción.
3. THE **Repo** SHALL contener un archivo `.pre-commit-config.yaml` en la raíz con hooks para `terraform fmt`, `terraform validate`, `tflint`, `checkov` y `terraform-docs`, donde cada entrada incluya un campo `rev:` con una etiqueta de versión concreta (no vacía, no `latest`, no SHA abreviado de menos de 7 caracteres).
4. WHEN se ejecuta `pre-commit run --all-files` en un entorno con todas las herramientas declaradas en `.pre-commit-config.yaml` instaladas, THE **pre-commit** SHALL completar todos los hooks con código de salida `0` sobre los archivos de los módulos `infra/modules/kms/` e `infra/bootstrap/`.
5. IF algún hook de `pre-commit` no encuentra el binario correspondiente (`tflint`, `checkov` o `terraform-docs`) en el `PATH`, THEN THE **pre-commit** SHALL terminar con código de salida distinto de `0` y emitir un mensaje indicando qué herramienta falta.

> *Traza a product.md*: "calidad: terraform fmt, terraform validate, tflint (ruleset aws), checkov, terraform test con mock_provider, terraform-docs, pre-commit" (tech.md).

---

### Requisito 7: Módulo `kms` – patrón de referencia para módulos reutilizables

**User Story:** Como ingeniero de infraestructura, quiero un módulo `kms` que sirva como patrón de referencia estructural para todos los módulos del proyecto, para que los módulos futuros sigan la misma estructura de archivos, convenciones de variables y estrategia de tests.

#### Criterios de aceptación

1. THE **Módulo_KMS** SHALL contener exactamente los archivos `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md` y `tests/kms_test.tftest.hcl`.
2. THE **Módulo_KMS** SHALL crear un recurso `aws_kms_key` con `enable_key_rotation = true`, `deletion_window_in_days` parametrizable con valor entero entre 7 y 30 validado mediante bloque `validation`, `description` parametrizable como `string` de hasta 256 caracteres y `policy` parametrizable como `string` JSON válido.
3. THE **Módulo_KMS** SHALL crear un recurso `aws_kms_alias` cuyo `name` sea una variable `alias_name` de tipo `string` con formato `alias/<prefijo>` validado mediante expresión regular `^alias/[a-zA-Z0-9/_-]+$` y longitud máxima de 256 caracteres, y cuyo `target_key_id` apunte al `key_id` del recurso `aws_kms_key` creado por el módulo.
4. THE **Módulo_KMS** SHALL exponer en `outputs.tf` exactamente los atributos `key_id`, `key_arn` y `alias_arn`, cada uno con `description` no vacía.
5. THE **Módulo_KMS** SHALL declarar en `variables.tf` todas las variables con `description` no vacía, `type` explícito y bloque `validation` en las variables `deletion_window_in_days` y `alias_name`; ninguna variable SHALL omitir el campo `description`.
6. THE **Módulo_KMS** SHALL declarar en `versions.tf` la versión requerida de Terraform `>= 1.10` y el provider `hashicorp/aws` con constraint `~> 6.73`.
7. WHEN se ejecuta `terraform validate` dentro de `infra/modules/kms/`, THE **Terraform_CLI** SHALL completar sin errores ni advertencias en la salida estándar.
8. WHEN se ejecuta `terraform test` dentro de `infra/modules/kms/`, THE **Terraform_CLI** SHALL ejecutar el archivo `tests/kms_test.tftest.hcl` usando `mock_provider "aws" {}` y SHALL completar con estado `pass` para todos los bloques `run` declarados en ese archivo, sin errores en la salida estándar.
9. IF la variable `policy` recibe una cadena vacía, THEN THE **Módulo_KMS** SHALL asignar `null` al argumento `policy` del recurso `aws_kms_key`, dejando que AWS aplique la política predeterminada de la clave.

> *Traza a product.md*: "cifrado en reposo" (KMS es el pilar de cifrado de toda la plataforma); "servicios gestionados y de bajo mantenimiento" (módulo reutilizable reduce duplicación).

---

### Requisito 8: Tests del módulo `kms` con mock_provider

**User Story:** Como ingeniero de calidad, quiero que el módulo `kms` tenga tests que se ejecuten sin credenciales AWS reales, para que el pipeline CI pueda verificar la lógica del módulo en cada pull request sin necesidad de acceso a una cuenta de AWS.

#### Criterios de aceptación

1. THE **Módulo_KMS** SHALL contener en `tests/kms_test.tftest.hcl` al menos un bloque `run` que use `mock_provider "aws" {}` para simular el provider sin credenciales reales, con un bloque `variables {}` que asigne a `deletion_window_in_days` un valor entero entre 7 y 30 inclusive y a `alias_name` un valor en formato `alias/<nombre>`.
2. WHEN el test se ejecuta con entradas válidas, THE **Terraform_CLI** SHALL evaluar un bloque `assert` que verifique que `aws_kms_key.this.enable_key_rotation` es `true`.
3. WHEN el test se ejecuta con entradas válidas, THE **Terraform_CLI** SHALL evaluar un bloque `assert` que verifique que `aws_kms_key.this.deletion_window_in_days` tiene un valor mayor o igual a 7 y menor o igual a 30.
4. WHEN el test se ejecuta con entradas válidas, THE **Terraform_CLI** SHALL evaluar un bloque `assert` que verifique que `aws_kms_alias.this.name` comienza con el prefijo `alias/`.
5. IF el test recibe un valor de `deletion_window_in_days` fuera del rango permitido (< 7 o > 30), THEN THE **Terraform_CLI** SHALL registrar ese fallo esperado mediante `expect_failures = [var.deletion_window_in_days]` en el bloque `run` correspondiente, de modo que el bloque `run` termine con estado exitoso sin ejecutar el plan.
6. WHEN se ejecuta `terraform test` en `infra/modules/kms/`, THE **Terraform_CLI** SHALL completar todos los bloques `run` con código de salida 0 y cero aserciones fallidas, usando únicamente `mock_provider "aws" {}` sin credenciales AWS configuradas en el entorno.
7. THE **Módulo_KMS** SHALL contener en `tests/kms_test.tftest.hcl` un bloque `run` dedicado a la ruta negativa, con un bloque `variables {}` que asigne a `deletion_window_in_days` un valor entero fuera del rango permitido (< 7 o > 30) y declare `expect_failures = [var.deletion_window_in_days]`.

> *Traza a product.md*: "terraform test con mock_provider" (tech.md); validación sin despliegue real (restricción del contexto de prueba técnica).

---

### Requisito 9: ADR-001 – Estructura del repositorio y herramientas Terraform

**User Story:** Como evaluador técnico de SDG Group, quiero un ADR que justifique las elecciones de Terraform >= 1.10, backend S3 con `use_lockfile`, estructura multicuenta y herramientas de calidad, para que el proceso de toma de decisiones quede documentado y sea evaluable.

#### Criterios de aceptación

1. THE **Repo** SHALL contener el archivo `docs/adr/ADR-001-terraform-estructura-repositorio.md` con las secciones: Contexto, Opciones evaluadas, Decisión y Consecuencias; donde cada sección contiene al menos un párrafo de texto sustantivo (no vacío ni placeholder).
2. THE **Repo** SHALL incluir en ADR-001 la justificación de Terraform >= 1.10 frente a versiones anteriores, mencionando explícitamente `use_lockfile = true` como característica clave que reemplaza el locking por DynamoDB y reduciendo recursos gestionados.
3. THE **Repo** SHALL incluir en ADR-001 la justificación de la estructura multicuenta con `provider assume_role` frente a un monorepo de cuenta única, indicando al menos dos ventajas concretas (por ejemplo: blast radius reducido, separación de blast radius entre entornos, permisos mínimos por rol de despliegue).
4. THE **Repo** SHALL incluir en ADR-001 la comparativa entre módulos reutilizables en `infra/modules/` con composición en `live/` frente a composición directa sin módulos y frente a Terragrunt como herramienta de composición, señalando al menos una ventaja y una limitación de cada enfoque.
5. THE **Repo** SHALL incluir en ADR-001 la justificación del conjunto de herramientas `tflint` + `checkov` + `pre-commit` frente a Trivy (escaneo de IaC y contenedores) y Terrascan (políticas OPA/Rego), indicando el criterio de selección utilizado (cobertura de reglas para AWS, integración nativa con GitHub Actions SARIF, curva de adopción).
6. IF el archivo `docs/adr/ADR-001-terraform-estructura-repositorio.md` no existe en la ruta indicada, THEN THE **Repo** SHALL fallar la validación de estructura de documentación con un mensaje indicando la ruta esperada del archivo faltante.

> *Traza a product.md*: "Se valora el PROCESO de decisión: cada decisión relevante se documenta como ADR".

---

### Requisito 10: ADR-002 – Bloqueo de estado con `use_lockfile`

**User Story:** Como evaluador técnico de SDG Group, quiero un ADR que justifique el uso de `use_lockfile = true` en lugar de la tabla DynamoDB tradicional para el locking del estado de Terraform, para que la decisión quede documentada con su comparativa técnica, ventajas y riesgos.

#### Criterios de aceptación

1. THE **Repo** SHALL contener el archivo `docs/adr/ADR-002-bloqueo-estado-use-lockfile.md` con las secciones: Contexto, Opciones evaluadas, Decisión y Consecuencias, donde cada sección es no vacía.
2. THE **Repo** SHALL incluir en ADR-002 una descripción técnica de `use_lockfile = true` especificando que fue introducido en Terraform 1.10, que almacena un objeto de bloqueo con el sufijo `.tflock` en el mismo bucket S3 que el archivo de estado, y que no requiere tabla DynamoDB.
3. THE **Repo** SHALL incluir en ADR-002 una tabla comparativa entre `use_lockfile = true` y el mecanismo de locking basado en DynamoDB que cubra al menos: coste mensual (DynamoDB on-demand ~0,25 $/millón de escrituras + tabla activa vs. objeto S3 con coste marginal de escritura); número de recursos AWS adicionales requeridos (1 tabla DynamoDB vs. 0 recursos extra); procedimiento de desbloqueo (ambos mecanismos requieren `terraform force-unlock <LOCK_ID>` o eliminación manual del recurso de bloqueo); y estado de soporte (locking con DynamoDB marcado como deprecado en Terraform 1.10 en favor de `use_lockfile`).
4. THE **Repo** SHALL incluir en ADR-002 las siguientes tres ventajas de `use_lockfile = true`: coste cero para operaciones de locking, eliminación de la dependencia en DynamoDB y soporte nativo en S3 disponible desde Terraform 1.10.
5. THE **Repo** SHALL incluir en ADR-002 una subsección de riesgos y mitigaciones que identifique el escenario de lock huérfano (el objeto de bloqueo persiste si el proceso Terraform termina de forma anormal) y especifique el procedimiento de desbloqueo manual: ejecutar `terraform force-unlock <LOCK_ID>` o eliminar directamente el objeto `.tflock` del bucket S3.

> *Traza a product.md*: "Se valora el PROCESO de decisión"; "backend S3 con use_lockfile = true, sin DynamoDB para locking" (tech.md).

---

### Requisito 11: Validación CI-only sin credenciales AWS

**User Story:** Como ingeniero de CI/CD, quiero que todo el código Terraform del spec `foundation` pueda validarse en el pipeline sin credenciales AWS reales, para que las comprobaciones sean reproducibles en cualquier entorno y no dependan de acceso a una cuenta AWS.

#### Criterios de aceptación

1. WHEN se ejecuta `terraform validate` en `infra/bootstrap/`, THE **Terraform_CLI** SHALL completar sin errores y con código de salida 0, usando únicamente el provider `hashicorp/aws ~> 6.73` sin credenciales configuradas.
2. WHEN se ejecuta `terraform validate` en `infra/modules/kms/`, THE **Terraform_CLI** SHALL completar sin errores y con código de salida 0 sin credenciales configuradas.
3. WHEN se ejecuta `terraform test` en `infra/modules/kms/`, THE **Terraform_CLI** SHALL completar todos los `run` blocks con resultado `pass` usando `mock_provider "aws" {}`, sin credenciales AWS y con código de salida 0.
4. THE **Sistema_CI** SHALL ejecutar `terraform validate` y `terraform test` con `mock_provider` sin que las variables de entorno `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` ni `AWS_SESSION_TOKEN` estén presentes en el entorno del proceso.
5. IF un archivo Terraform contiene un argumento no reconocido por el provider `hashicorp/aws ~> 6.73`, THEN THE **Terraform_CLI** SHALL producir un error de validación con código de salida distinto de 0 que identifique el nombre del argumento incorrecto y el recurso que lo contiene.
6. IF `terraform validate` o `terraform test` producen un código de salida distinto de 0 en cualquier módulo del spec `foundation`, THEN THE **Sistema_CI** SHALL marcar el pipeline como fallido e interrumpir los pasos posteriores sin ejecutar ningún `terraform plan` ni `terraform apply`.

> *Traza a product.md*: "NO es obligatorio ejecutar el despliegue" (product.md); restricción explícita del contexto de prueba técnica.

---

### Requisito 12: Etiquetado obligatorio mediante `default_tags`

**User Story:** Como gestor de costes y cumplimiento, quiero que todos los recursos AWS creados por el código Terraform lleven las etiquetas obligatorias definidas en `structure.md`, para que el inventario de recursos sea trazable por proyecto, entorno, propietario y centro de coste.

#### Criterios de aceptación

1. THE **Sistema_CI** SHALL configurar cada instancia del provider `hashicorp/aws` — incluyendo instancias con alias de región — con un bloque `default_tags` que incluya exactamente las etiquetas `Project`, `Environment`, `Owner`, `CostCenter`, `ManagedBy` (valor fijo `"terraform"`) y `DataClassification`.
2. THE **Sistema_CI** SHALL declarar `Project`, `Environment`, `Owner`, `CostCenter` y `DataClassification` como variables Terraform sin valor por defecto (`default` omitido) y con una regla `validation` que rechace cualquier valor cuya longitud sea cero o cuyo contenido sea exclusivamente espacios en blanco, emitiendo un mensaje de error que identifique la variable afectada.
3. IF un módulo de `infra/modules/` declara un argumento `tags` en algún recurso, THEN THE **Sistema_CI** SHALL no incluir en ese argumento ninguna de las claves `Project`, `Environment`, `Owner`, `CostCenter`, `ManagedBy` ni `DataClassification`, de modo que `default_tags` sea la única fuente de esas claves.
4. WHEN se ejecuta `terraform validate` en cualquier carpeta de `infra/`, THE **Terraform_CLI** SHALL terminar con código de salida `0` y no emitir ningún mensaje de error en la salida estándar de error.

> *Traza a product.md*: "Etiquetas obligatorias vía default_tags del provider" (structure.md); "Herramientas de monitorización de coste y rendimiento" (product.md).
