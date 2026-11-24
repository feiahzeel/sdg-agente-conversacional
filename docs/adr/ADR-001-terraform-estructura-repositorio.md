# ADR-001: Terraform, estructura del repositorio y herramientas de calidad

- **Estado:** Aceptada
- **Ámbito:** `infra/`, `.tflint.hcl`, `.checkov.yaml`, `.pre-commit-config.yaml`

## Contexto

El proyecto es una prueba técnica de SDG Group que debe demostrar buenas prácticas de infraestructura como código en AWS. La plataforma se reparte entre varias cuentas (Networking, DevOps, Workload-Dev, Workload-Pre, Workload-Prod y DR) y varios entornos. El código debe reutilizarse entre entornos sin duplicarse.

Los pipelines de CI/CD deben autenticarse sin secretos de AWS almacenados en GitHub, mediante OIDC y roles de despliegue por cuenta. El despliegue no es obligatorio, pero el código tiene que ser evaluable: debe pasar `terraform validate`, `terraform test` y las comprobaciones estáticas sin credenciales reales. Se valora el proceso de decisión, por lo que cada elección relevante queda documentada.

Hay también una decisión sobre la versión de Terraform. Hasta la 1.9, el backend S3 solo permitía bloquear el estado con una tabla DynamoDB. Terraform 1.10 introdujo `use_lockfile = true`, que guarda un objeto `.tflock` en el propio bucket. La 1.11 lo declaró estable y marcó `dynamodb_table` como deprecado. El detalle del bloqueo se documenta en ADR-002.

## Opciones evaluadas

### Estructura del código

**A. Terraform monolítico en una cuenta única.**
- Ventaja: es la forma más simple de empezar, con un solo estado y un solo provider.
- Limitación: no escala a un modelo multicuenta. Cualquier cambio toca un único estado, de modo que el blast radius es máximo. Además, un único rol necesita permisos sobre todo.

**B. Módulos reutilizables en `infra/modules/` y composición en `infra/live/`, con `provider assume_role` por cuenta.**
- Ventaja: un estado por carpeta de `live/` limita el blast radius. Los roles `plan` y `apply` pueden tener permisos distintos, y cada cuenta se alcanza asumiendo su rol de despliegue.
- Limitación: mayor complejidad inicial, con más archivos y providers con alias. Hay algo de repetición de cabeceras (backend, providers) entre carpetas de `live/`.

**C. Terragrunt como herramienta de composición.**
- Ventaja: reduce la repetición (DRY) de backend y providers, y gestiona dependencias entre estados.
- Limitación: añade una dependencia externa y una curva de aprendizaje. Complica el CI/CD y los roles OIDC, y los evaluadores deben conocer una herramienta más.

### Versión de Terraform

Se compara Terraform < 1.10 (bloqueo con DynamoDB) con Terraform >= 1.10 (`use_lockfile = true`).

### Herramientas de calidad

| Herramienta | Cobertura AWS | Integración con GitHub (SARIF) | Curva de adopción |
|---|---|---|---|
| tflint (ruleset aws) | Valida argumentos y valores específicos del provider que `terraform validate` no detecta | No aplica (lint, no seguridad) | Baja |
| checkov | Más de 1.000 checks para AWS, con análisis de grafo entre recursos | Salida SARIF nativa | Baja |
| Trivy | Menor cobertura de políticas de IaC para AWS; sin análisis de grafo | Soporta SARIF | Baja |
| Terrascan | Políticas OPA/Rego | Integración más limitada | Alta (Rego) |

## Decisión

Se adopta la **opción B**: módulos reutilizables en `infra/modules/`, composición por cuenta y entorno en `infra/live/` (un estado por carpeta) y providers con alias que asumen un rol de despliegue en cada cuenta (`assume_role`).

Se justifica por dos ventajas concretas:

1. **Blast radius reducido.** Un fallo o un `apply` erróneo en `workload/prod` no afecta al estado de `networking` ni al de `devops`.
2. **Permisos mínimos diferenciados por rol.** Los pipelines usan un rol `plan` de solo lectura y un rol `apply` con permisos de escritura, ambos federados por OIDC. Cada uno asume en la cuenta destino su rol correspondiente (`chatbot-plan-role` o `chatbot-deploy-role`).

Se descarta A porque no admite multicuenta, y C porque su beneficio de DRY no compensa la dependencia adicional para un repositorio de este tamaño.

Se fija **Terraform >= 1.10** con backend S3 y `use_lockfile = true`. Esto elimina la tabla DynamoDB de bloqueo, un recurso menos que gestionar, pagar y proteger. El proveedor `hashicorp/aws` se fija en `~> 6.73`.

Para la calidad se adopta el conjunto **`tflint` + `checkov` + `pre-commit`**:

- **tflint** con el ruleset de AWS detecta errores que `terraform validate` no ve, como valores inválidos de argumentos del provider. Aporta además reglas de convención de nombres y tipado de variables. Trivy y Terrascan no cubren este caso, porque son escáneres de seguridad y no linters del provider.
- **checkov** se elige por su cobertura de reglas para AWS, el análisis de grafo entre recursos (por ejemplo, comprobar que una clave KMS tiene política de uso restringido) y la salida SARIF nativa para GitHub Security.
- **pre-commit** ejecuta `terraform fmt`, `validate`, `tflint`, `checkov` y `terraform-docs` en local antes del commit, lo que acorta el ciclo de feedback.

## Consecuencias

- Cada carpeta de `live/` tiene su propio estado, con clave de backend igual a su ruta. Un error queda acotado a esa carpeta.
- La separación plan/apply con roles distintos permite que las pull requests solo puedan leer.
- No hay dependencia de Terragrunt, a costa de repetir cabeceras de backend y providers entre carpetas de `live/`.
- El bloqueo de estado no necesita DynamoDB. El riesgo es un lock huérfano (objeto `.tflock` que queda tras un fallo), que se resuelve con `terraform force-unlock` y se describe en ADR-002.
- **tflint frente a Trivy y Terrascan:** tflint cubre el lint específico del provider de AWS. Trivy y Terrascan se centran en seguridad, donde ya está checkov. Añadirlos duplicaría reglas y ruido. Trivy podría incorporarse más adelante para escanear imágenes de contenedor, que hoy quedan fuera del alcance.
- **checkov:** requiere mantener la lista `skip-check` de `.checkov.yaml`. Cada exclusión lleva un comentario con su justificación. Por ejemplo, `CKV2_AWS_64` puede excluirse en el módulo `kms` porque la política de la clave la aporta el llamador mediante `var.policy`.
- **Plan de bootstrap manual:** `infra/bootstrap/` crea el bucket de estado, el proveedor OIDC de GitHub y los roles de despliegue. No puede usar los roles que él mismo crea, por lo que se aplica una sola vez en local con credenciales de administrador y estado local. Después se migra el estado al bucket S3 con `terraform init -migrate-state`. Por esa razón, `terraform plan` y `apply` sobre `infra/bootstrap/` se ejecutan manualmente y no desde CI. El resto de carpetas de `live/` se despliega con roles OIDC sin credenciales estáticas.
- La verificación no requiere cuentas reales: se apoya en `terraform validate` y `terraform test` con `mock_provider`.
