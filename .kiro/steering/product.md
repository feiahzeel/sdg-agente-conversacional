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
