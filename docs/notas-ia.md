# Notas de uso de IA

Registro de cada corrección hecha a la IA durante el diseño y la implementación. Alimenta la sección "Uso de IA en el proceso" del README.

| Fecha | Herramienta | Fase (requirements / design / tasks / código) | Qué propuso la IA | Qué decidí y por qué | ADR relacionado |
| --- | --- | --- | --- | --- | --- |
| 2026-11-19 | Claude | Diseño landing zone | Cuenta Management dentro de una OU | La cuenta de gestión está en la raíz; no puede ir en una OU | ADR-011 |
| 2026-11-19 | Claude | Diseño landing zone | KMS centralizado en Security Tooling | Una CMK por cuenta para limitar el radio de impacto | ADR-010 |
| 2026-11-20 | Claude | Diagrama | Línea directa del TGW al ALB | El TGW entra por el attachment de la VPC; corregido en el diagrama | — |
