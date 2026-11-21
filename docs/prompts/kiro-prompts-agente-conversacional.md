# Kit para Kiro – Agente conversacional en AWS (prueba SDG)

Orden de uso:

1. Configurar los MCP (sección 1).
2. Crear los ficheros de steering (sección 2).
3. Lanzar los specs **uno a uno**, revisando requirements → design → tasks antes de ejecutar (sección 3).
4. Ejecutar las tareas.
5. Generar el coste (sección 4), el inventario (sección 5) y la documentación final (sección 6).

Pon el PDF del diagrama en `docs/arquitectura/diagrama-lld.pdf` y el Excel en `docs/SDG_Prueba_Mapeo_AWS.xlsx` antes de empezar, para poder referenciarlos.

---

## 1. MCP servers – `.kiro/settings/mcp.json` (en el repo)

```json
{
  "mcpServers": {
    "terraform": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "hashicorp/terraform-mcp-server"],
      "disabled": false,
      "autoApprove": []
    },
    "awslabs.aws-pricing-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.aws-pricing-mcp-server@latest"],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR",
        "AWS_PROFILE": "pricing",
        "AWS_REGION": "us-east-1"
      },
      "disabled": false,
      "autoApprove": []
    },
    "awslabs.aws-documentation-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server@latest"],
      "env": { "FASTMCP_LOG_LEVEL": "ERROR" },
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

Notas:
- `AWS_REGION` del MCP de precios es la región **del endpoint de la Price List API** (us-east-1, eu-central-1 o ap-south-1), no la región de la arquitectura. Los precios se piden para eu-west-1 en el prompt.
- El perfil `pricing` solo necesita la política `pricing:*` (la API es gratuita).
- Requiere Docker (Terraform MCP) y `uv` instalado (`uvx`).

---

## 2. Steering – `.kiro/steering/`

### 2.1 `product.md`

```markdown
---
inclusion: always
---
# Producto: plataforma de un agente conversacional en AWS

Prueba técnica para SDG Group (Data & AI Infrastructure Practice). Hay que entregar:
1. Diseño de bajo nivel (ya hecho: docs/arquitectura/diagrama-lld.pdf).
2. Código Terraform de TODA la infraestructura.
3. Pipelines de CI/CD que la despliegan. NO es obligatorio ejecutar el despliegue.

Se valora el PROCESO de decisión: cada decisión relevante se documenta como ADR en docs/adr/.

Alcance:
- SOLO infraestructura. El código de la aplicación (Angular, .NET/Java, lógica RAG) queda fuera; los servicios ECS usan una imagen placeholder parametrizable.
- La conexión con on-prem (VPN/Direct Connect hacia SAP) se modela con variables y queda deshabilitada por defecto (`enable_vpn = false`).
- Power BI y Entra ID solo hay que "hacerlos disponibles" (gateway de Power BI, OIDC en el ALB).

Requisitos no funcionales del enunciado (todos deben quedar trazados en requirements.md):
- Plataforma en red privada; las comunicaciones entre servicios no pasan por internet.
- Topología que permita a otras VPC alcanzar la API conversacional en el futuro (PrivateLink).
- Cifrado en reposo y en tránsito.
- Resiliencia ante desastre (pilot light en eu-central-1).
- Servicios gestionados y de bajo mantenimiento.
- Usuarios autenticados (Entra ID, OIDC en el ALB).
- Herramientas de monitorización de coste y rendimiento.
- Optimización coste/beneficio.

Idioma: requirements.md, design.md, tasks.md, ADRs y README en ESPAÑOL. Código, nombres de recursos y comentarios técnicos en inglés.
```

### 2.2 `tech.md`

```markdown
---
inclusion: always
---
# Decisiones técnicas (NO cambiarlas sin proponer un ADR)

Regiones: principal eu-west-1 (Irlanda); DR eu-central-1 (Fráncfort), estrategia pilot light.

Cuentas (AWS Organizations + Control Tower; la landing zone se asume existente):
- Networking: Transit Gateway (compartido por RAM), VPC de egress/inspección (IGW + NAT + AWS Network Firewall, appliance mode), VPC de endpoints centralizados (bedrock-runtime, bedrock-agent-runtime, ecr.api, ecr.dkr, secretsmanager, kms, logs, sts, monitoring), Route 53 Profiles, Route 53 Resolver inbound endpoint, VPN Site-to-Site (deshabilitada por defecto).
- DevOps: ECR (política para la organización con aws:PrincipalOrgID, escaneo, tags inmutables, replicación a eu-central-1), bucket S3 del estado de Terraform, proveedor OIDC de GitHub y roles de despliegue.
- Workload-Dev / Workload-Pre / Workload-Prod: VPC privada SIN Internet Gateway, Multi-AZ (2 AZ en dev/pre, 3 en prod), tres capas de subred: tgw (/28 por AZ), app (ALB, Fargate, NLB, EC2), data (Aurora).
- Security (Log Archive, Audit): solo referencias; no se despliegan aquí.

Servicios de la carga de trabajo:
- ALB interno, listener 443 con certificado ACM (chat.empresa.com), política TLS13, acción authenticate-oidc contra Entra ID + forward. Listener 80 solo redirige a 443. Ruta /api/* con on_unauthenticated_request = deny. session_timeout = 28800.
- ECS Fargate: servicios frontend, chatbot-backend y conversational-api, con ECS Service Connect, auto scaling, Container Insights, task role y execution role separados, readonlyRootFilesystem cuando sea posible.
- NLB interno + VPC Endpoint Service (acceptance_required = true, allowed_principals por variable) delante de conversational-api.
- Aurora PostgreSQL Serverless v2 con pgvector, Multi-AZ, Data API habilitado (lo requiere Bedrock Knowledge Bases), credenciales en Secrets Manager con rotación, cifrado con CMK, Aurora Global Database con secundario en eu-central-1 (solo prod).
- DynamoDB on-demand (tracker store: memoria conversacional + observabilidad), PITR, TTL, CMK, Global Table con réplica en eu-central-1 (solo prod).
- S3 de documentos (PDFs, manuales, facturas) para la Knowledge Base: bloqueo de acceso público, versionado, SSE-KMS, política que solo admite acceso por VPC endpoint/rol de Bedrock.
- Amazon Bedrock: Knowledge Base con Aurora pgvector como vector store, modelo de embeddings y LLM por variable, logging de invocaciones a CloudWatch/S3 cifrado, IAM limitado a los ARN de modelo aprobados, Guardrail opcional.
- EC2 Windows Server para el on-premises data gateway de Power BI: subred app, sin IP pública, acceso solo por SSM Session Manager, IMDSv2, EBS cifrado.
- KMS: una CMK por cuenta y propósito (data, logs), rotación anual activada.

Red y seguridad:
- Plan de CIDR (variables con estos valores por defecto): egress 10.0.0.0/22, endpoints 10.0.4.0/22, workload-prod 10.10.0.0/16, workload-pre 10.20.0.0/16, workload-dev 10.30.0.0/16, DR 10.110.0.0/16, on-prem 192.168.0.0/16 (placeholder).
- Tablas de rutas del TGW: prod, nonprod, egress, endpoints, on-prem; nonprod no llega a prod.
- Network Firewall: stateful, por defecto deny; allowlist de dominios (SNI/HTTP host): login.microsoftonline.com, graph.microsoft.com, public-keys.auth.elb.eu-west-1.amazonaws.com, *.powerbi.com, *.analysis.windows.net, *.servicebus.windows.net. Logs de alertas y flujo en CloudWatch.
- Security groups: ALB 443 solo desde CIDR corporativos; tareas solo desde el SG del ALB/NLB o vía Service Connect; Aurora 5432 solo desde conversational-api, gateway de Power BI y Bedrock KB (Data API no usa SG); endpoints 443 desde los CIDR de las VPC de workload.
- VPC Flow Logs en todas las VPC.
- Nada de IAM users ni claves estáticas. Mínimo privilegio. Sin "*" en acciones salvo justificación documentada.

Observabilidad y coste: CloudWatch dashboards y alarmas (5xx del ALB, CPU/memoria ECS, ACU de Aurora, throttling de DynamoDB y Bedrock), X-Ray, AWS Budgets por entorno, Cost Anomaly Detection.

Herramientas:
- Terraform >= 1.10 (backend S3 con use_lockfile = true, sin DynamoDB para locking).
- Provider hashicorp/aws en la versión estable más reciente; CONSULTAR EL MCP de Terraform para confirmar versión y argumentos de cada recurso antes de escribirlo. No inventar argumentos.
- Módulos de comunidad permitidos solo para piezas estándar (terraform-aws-modules/vpc, etc.) con versión fijada; justificar en ADR.
- Calidad: terraform fmt, terraform validate, tflint (ruleset aws), checkov, terraform test con mock_provider, terraform-docs, pre-commit.
- CI/CD: GitHub Actions con OIDC (aws-actions/configure-aws-credentials), sin secretos de AWS en GitHub.
```

### 2.3 `structure.md`

```markdown
---
inclusion: always
---
# Estructura del repositorio

.
├── .github/workflows/        # pr.yml, apply.yml, drift.yml, images.yml (opcional)
├── docs/
│   ├── arquitectura/         # diagrama-lld.pdf, diagrama.md (mermaid)
│   ├── adr/                  # ADR-001-*.md (formato: contexto, opciones, decisión, consecuencias)
│   ├── costes/               # coste-mensual.md, coste-mensual.csv
│   └── inventario/           # inventario.md
├── infra/
│   ├── bootstrap/            # bucket de estado, proveedor OIDC de GitHub, roles de despliegue (se aplica una vez, en local)
│   ├── modules/              # módulos reutilizables, uno por responsabilidad
│   │   ├── tgw-hub/  egress-inspection/  central-endpoints/  dns/
│   │   ├── workload-vpc/  alb-oidc/  ecs-platform/  ecs-service/
│   │   ├── privatelink-service/  aurora-pgvector/  dynamodb-tracker/
│   │   ├── bedrock-kb/  documents-bucket/  ecr/  kms/
│   │   ├── powerbi-gateway/  observability/  budgets/
│   └── live/                 # composición por cuenta y entorno; cada carpeta = un estado
│       ├── networking/eu-west-1/
│       ├── devops/eu-west-1/
│       ├── workload/dev/  workload/pre/  workload/prod/
│       └── dr/eu-central-1/
└── tests/                    # o tests/ dentro de cada módulo (*.tftest.hcl)

Convenciones:
- Cada módulo: main.tf, variables.tf (con description, type y validation), outputs.tf, versions.tf, README.md (terraform-docs), tests/*.tftest.hcl.
- Nombres: <proyecto>-<entorno>-<componente>, proyecto = "chatbot" (ej.: chatbot-prod-alb).
- Etiquetas obligatorias vía default_tags del provider: Project, Environment, Owner, CostCenter, ManagedBy=terraform, DataClassification.
- Un estado por carpeta de live/, clave del backend = ruta de la carpeta.
- Multicuenta con provider assume_role (rol de despliegue por cuenta); nada de credenciales en código.
- Los valores por entorno van en terraform.tfvars de cada carpeta live/; ningún valor de entorno dentro de modules/.
```

### 2.4 Hook recomendado (crearlo desde el panel de Hooks de Kiro)

> Cuando se guarde un fichero `*.tf` o `*.tftest.hcl`, ejecutar `terraform fmt -recursive infra/` y `tflint --recursive` y mostrar los errores. No modificar otros ficheros.

---

## 3. Specs (lanzar UNO A UNO, en este orden)

Antes de cada spec, añade al chat el PDF del diagrama como contexto. Revisa y corrige requirements.md antes de aceptar el design, y el design antes de generar tasks.

### Spec 1 – `foundation` (bootstrap + estructura + calidad)

```
Crea un spec llamado "foundation" para preparar el repositorio de infraestructura del agente conversacional descrito en los ficheros de steering y en #docs/arquitectura/diagrama-lld.pdf.

Debe incluir:
1. La estructura de carpetas de structure.md.
2. infra/bootstrap: bucket S3 de estado (versionado, SSE-KMS, bloqueo de acceso público, política que exige TLS), proveedor OIDC de GitHub en la cuenta DevOps, rol "github-terraform-plan" (solo lectura, PRs) y rol "github-terraform-apply" (rama main y environments), y en cada cuenta destino un rol de despliegue asumible desde esos roles.
3. Configuración de calidad: .tflint.hcl con el ruleset de AWS, .checkov.yaml, .pre-commit-config.yaml (fmt, validate, tflint, checkov, terraform-docs), .gitignore de Terraform.
4. Un módulo de ejemplo "kms" con su test (terraform test + mock_provider) para fijar el patrón que seguirán los demás módulos.
5. ADR-001 (Terraform y estructura de repo), ADR-002 (bloqueo con use_lockfile).

Usa el MCP de Terraform para confirmar la versión actual del provider aws y los argumentos de cada recurso. Requisitos en formato EARS y trazables a product.md.
```

### Spec 2 – `networking` (cuenta Networking + VPC de workload)

```
Crea un spec llamado "networking" con:
- Módulo tgw-hub: Transit Gateway (auto-accept off, default route table association/propagation off), tablas de rutas prod, nonprod, egress, endpoints y on-prem, compartición por RAM con la organización, VPN Site-to-Site opcional (enable_vpn = false).
- Módulo egress-inspection: VPC con subredes tgw, firewall y public por AZ; IGW; un NAT por AZ; AWS Network Firewall con política stateful por defecto deny y allowlist de dominios de tech.md; attachment con appliance mode; tablas de rutas por AZ para simetría; logs del firewall en CloudWatch.
- Módulo central-endpoints: VPC de endpoints con interface endpoints (bedrock-runtime, bedrock-agent-runtime, ecr.api, ecr.dkr, secretsmanager, kms, logs, sts, monitoring), private DNS desactivado y zonas privadas de Route 53 por servicio compartidas con Route 53 Profiles; endpoint policies que limitan a la organización (aws:PrincipalOrgID / aws:ResourceOrgID).
- Módulo dns: Route 53 Resolver inbound endpoint (2 AZ) y zona privada chat.empresa.com.
- Módulo workload-vpc: VPC sin IGW, subredes tgw/app/data por AZ, attachment al TGW compartido, rutas 0.0.0.0/0 y CIDR on-prem hacia el TGW, gateway endpoints S3 y DynamoDB, VPC Flow Logs, asociación al Route 53 Profile.
- Composición en live/networking/eu-west-1 y la parte de red de live/workload/{dev,pre,prod}.
- Tests: rutas esperadas, que la VPC de workload no tenga IGW, appliance mode activo.
- ADRs: hub-and-spoke con TGW, endpoints centralizados (trade-off 0,02 USD/GB del TGW), egress centralizado con Network Firewall.
Usa el MCP de Terraform para cada recurso.
```

### Spec 3 – `workload-platform` (ALB, ECS, PrivateLink, datos, Bedrock, Power BI)

```
Crea un spec llamado "workload-platform" con los módulos alb-oidc, ecs-platform, ecs-service (reutilizable, instanciado 3 veces), privatelink-service, aurora-pgvector, dynamodb-tracker, documents-bucket, bedrock-kb, powerbi-gateway y su composición en live/workload/{dev,pre,prod}, según tech.md.

Requisitos clave a cubrir con criterios de aceptación EARS:
- El ALB solo reenvía tráfico autenticado por Entra ID (authenticate-oidc antes de forward en TODAS las reglas); client secret leído de Secrets Manager.
- Las tareas Fargate solo aceptan tráfico del ALB/NLB o de Service Connect.
- La API conversacional se publica como VPC Endpoint Service con aceptación manual.
- Aurora Serverless v2: pgvector, Data API, Multi-AZ, rotación de credenciales, CMK, min/max ACU por entorno; Global Database solo en prod.
- Bedrock Knowledge Base con S3 de documentos como fuente y Aurora pgvector como vector store; IAM limitado a los modelos indicados por variable; logging de invocaciones.
- EC2 Windows para Power BI gateway sin IP pública, SSM, IMDSv2.
- Tamaños de dev/pre reducidos (desired_count, ACU) mediante tfvars.
- Imagen de contenedor placeholder por variable (la app está fuera de alcance).
Tests con mock_provider para los módulos alb-oidc, ecs-service y aurora-pgvector.
ADRs: Fargate frente a EKS, PrivateLink para la API, Aurora+pgvector frente a Redshift+OpenSearch, OIDC en el ALB.
Usa el MCP de Terraform para cada recurso (en especial aws_lb_listener authenticate_oidc, aws_vpc_endpoint_service, aws_rds_cluster serverlessv2_scaling_configuration, aws_bedrockagent_knowledge_base).
```

### Spec 4 – `operations-dr` (DevOps, observabilidad, costes, DR)

```
Crea un spec llamado "operations-dr" con:
- live/devops: módulo ecr (repos frontend, chatbot-backend, conversational-api; escaneo al subir, tags inmutables, lifecycle, política de organización, replicación a eu-central-1).
- Módulo observability: dashboard por entorno y alarmas (ALB 5xx y latencia, ECS CPU/memoria, Aurora ACU y conexiones, DynamoDB throttling, Bedrock invocaciones/throttling, Network Firewall drops) con SNS.
- Módulo budgets: AWS Budgets por entorno con alertas al 80 % y 100 %, Cost Anomaly Detection.
- live/dr/eu-central-1: pilot light. Red mínima y recursos de datos secundarios (Aurora Global secundario, réplica de DynamoDB, ECR replicado) siempre activos; cómputo (ECS, ALB, NLB) detrás de una variable dr_activated = false.
- docs/runbooks/dr-failover.md con los pasos de failover y vuelta atrás.
- ADR: pilot light con RTO 4 h y RPO 15 min (supuestos).
```

### Spec 5 – `cicd` (GitHub Actions)

```
Crea un spec llamado "cicd" con los workflows de GitHub Actions:
- pr.yml (pull_request): detectar las carpetas de infra/live cambiadas (matrix), terraform fmt -check, validate, tflint, checkov (SARIF subido a GitHub Security), terraform test, terraform plan con rol de solo lectura vía OIDC, comentario del plan en el PR e Infracost con el impacto en coste.
- apply.yml (push a main): apply en dev automático; pre y prod con GitHub Environments y aprobación manual; orden: networking → devops → workload → dr.
- drift.yml (schedule semanal): terraform plan -detailed-exitcode y crear un issue si hay deriva.
- Permisos mínimos por job (id-token: write, contents: read, pull-requests: write solo donde haga falta), concurrency por stack, versiones de actions fijadas por SHA.
- docs/cicd.md explicando el flujo y cómo se configura OIDC.
- ADR: GitHub Actions frente a CodePipeline (mencionar runners en CodeBuild para entornos regulados).
```

### Prompt para ejecutar tareas (después de aprobar cada spec)

```
Ejecuta las tareas del spec <nombre> de una en una. Antes de escribir cada recurso, consulta el MCP de Terraform para validar argumentos y versión. Al terminar cada tarea ejecuta terraform fmt, terraform validate y terraform test del módulo afectado y corrige los errores antes de marcarla como completada. No avances a la siguiente tarea con errores.
```

---

## 4. Coste mensual con el MCP aws-pricing

```
Usa el MCP awslabs.aws-pricing-mcp-server para calcular el coste mensual de la infraestructura definida en infra/ (léela del código, no de memoria), región eu-west-1, precios On-Demand, 730 horas/mes.

Genera docs/costes/coste-mensual.md y docs/costes/coste-mensual.csv con ESTA tabla, en EUROS:
| Bloque | Concepto | Supuesto de dimensionamiento | Cantidad | Precio unitario (USD) | Unidad | ¿Por hora? | Coste mensual (USD) | Coste mensual (EUR) |

Reglas:
- Tipo de cambio USD→EUR en una variable visible al principio (TIPO_CAMBIO = <valor que te indique>, fuente y fecha). No inventes el tipo de cambio: pídemelo.
- Una fila por concepto facturable. Incluye como mínimo: Fargate vCPU y GB (por servicio), ALB (horas + LCU), NLB (horas + NLCU), interface endpoints (endpoint-AZ-hora + GB), Transit Gateway (attachments + GB procesado), NAT Gateway (horas + GB), Network Firewall (endpoint-hora + GB), Route 53 Resolver inbound endpoint (ENI-hora), Route 53 Profiles, zonas privadas, VPN (si enable_vpn), Aurora Serverless v2 (ACU-hora, almacenamiento, I/O), Aurora Global Database (réplica en eu-central-1), DynamoDB on-demand + PITR + Global Table, S3 (documentos y estado), EC2 Windows (t3.large o el tipo definido) + EBS, KMS (claves + peticiones), Secrets Manager, CloudWatch (logs, métricas, alarmas, dashboards), X-Ray, VPC Flow Logs, GuardDuty/Security Hub/Config (estimación), ECR (almacenamiento + replicación), Bedrock (ver abajo).
- Bedrock: tabla de supuestos aparte (usuarios 200, preguntas/usuario/día 10, días 22, tokens de entrada 3.000, tokens de salida 500, modelo LLM y de embeddings definidos en tfvars) y su coste. Incluye la ingesta de la Knowledge Base (embeddings del corpus inicial, supuesto: 5.000 páginas).
- Resumen final: Producción, Dev + Pre (calculado con los tamaños de sus tfvars, no con un porcentaje), DR pilot light (eu-central-1), Bedrock, TOTAL MENSUAL y TOTAL ANUAL, en USD y EUR.
- Marca con "(estimación)" toda cifra que no venga del MCP y explica el supuesto.
- Añade al final las palancas de optimización (Savings Plans, apagado de nonprod fuera de horario, NAT sin firewall en nonprod, elección de modelo de Bedrock) con el ahorro estimado de cada una.
- Indica la fecha de consulta de precios.
```

---

## 5. Inventario de lo desplegado

```
Genera docs/inventario/inventario.md a partir del CÓDIGO de infra/live (y, si existe, de la salida de `terraform show -json` de cada plan). Una tabla por cuenta y región con:
| Cuenta | Región | Stack (carpeta live) | Módulo | Tipo de recurso Terraform | Nombre lógico | Propósito | Multi-AZ | Cifrado (KMS) | Expuesto a internet (sí/no) | Etiquetas clave |

Después:
1. Un resumen con el número de recursos por cuenta y por tipo.
2. Una comprobación de cumplimiento: lista de recursos con "Expuesto a internet = sí" (solo debe aparecer el IGW/NAT de la VPC de egress), recursos sin cifrado y recursos sin las etiquetas obligatorias.
3. Un script scripts/inventory.sh que regenere el inventario con `terraform show -json` + jq, para usarlo tras un plan o un apply real.
```

---

## 6. Documentación final

```
Genera README.md en la raíz con: resumen de la solución, enlace al diagrama (docs/arquitectura), cómo se cumple cada requisito del enunciado (tabla de trazabilidad hacia requirements.md y ADRs), estructura del repo, cómo desplegar (bootstrap → networking → devops → workload → dr), cómo funcionan los pipelines, coste mensual (enlace a docs/costes), estimación de esfuerzo (enlace al Excel), y una sección "Uso de IA en el proceso" (Claude para diseño y revisión, Kiro con specs para el código, MCP de Terraform y de precios para validar, validación con fmt/validate/tflint/checkov/test). Incluye un diagrama mermaid de los stacks y su orden de despliegue.
```
