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
