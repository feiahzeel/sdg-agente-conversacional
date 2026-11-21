# Notas de uso de IA

Registro de cada corrección hecha a la IA durante el diseño y la implementación. Alimenta la sección "Uso de IA en el proceso" del README.

| Fecha | Herramienta | Fase (requirements / design / tasks / código) | Qué propuso la IA | Qué decidí y por qué | ADR relacionado |
| --- | --- | --- | --- | --- | --- |
| 2026-11-19 | Claude | Diseño landing zone | Cuenta Management dentro de una OU | La cuenta de gestión está en la raíz; no puede ir en una OU | ADR-011 |
| 2026-11-19 | Claude | Diseño landing zone | KMS centralizado en Security Tooling | Una CMK por cuenta para limitar el radio de impacto | ADR-010 |
| 2026-11-20 | Claude | Diagrama | Línea directa del TGW al ALB | El TGW entra por el attachment de la VPC; corregido en el diagrama | — |
| 2026-11-21 | Kiro | requirements foundation | Un único chatbot-deployment-role asumible por plan y apply | Dos roles por cuenta destino (plan solo lectura / deploy escritura) para no romper mínimo privilegio | ADR-001 |
| 2026-11-21 | Kiro | requirements foundation | Rol de plan con solo s3:GetObject/ListBucket | use_lockfile escribe .tflock también en plan: añadir Put/Delete sobre *.tflock y KMS | ADR-002 |
| 2026-11-21 | Kiro | requirements foundation | aws:ResourceTag para limitar creación y región única eu-west-1 | aws:RequestTag para crear; IAM es global; DR en eu-central-1 | — |
| 2026-11-21 | Kiro | requirements foundation | DynamoDB gestiona locks huérfanos por TTL; Terragrunt como alternativa a tflint/checkov | Ambos requieren force-unlock; Terragrunt es orquestación, alternativas reales Trivy/Terrascan | ADR-001, ADR-002 |
| 2026-11-21 | Kiro | requirements foundation | Filtro de severidad en checkov | Requiere API key de Prisma; todos los checks + excepciones justificadas | — |