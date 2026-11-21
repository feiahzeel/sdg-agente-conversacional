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
