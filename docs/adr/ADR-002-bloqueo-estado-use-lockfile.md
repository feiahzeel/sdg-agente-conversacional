# ADR-002: Bloqueo de estado con `use_lockfile`

- **Estado:** Aceptado
- **Ámbito:** backend S3 del estado de Terraform (bootstrap y carpetas `infra/live/`)

## Contexto

Terraform necesita un mecanismo de bloqueo (locking) para evitar que dos ejecuciones concurrentes de `plan`/`apply` escriban el mismo estado y lo corrompan. Este repositorio usa un estado por carpeta de `live/`, con ejecuciones desde GitHub Actions y desde local, por lo que la concurrencia es posible.

Historia del mecanismo en el backend S3:

- **Hasta Terraform 1.9:** el único método de locking era una tabla DynamoDB (argumento `dynamodb_table`), que obligaba a crear y mantener un recurso adicional.
- **Terraform 1.10:** introduce `use_lockfile = true` como característica experimental. Crea un objeto de bloqueo con sufijo `.tflock` en el mismo bucket S3 que el estado, mediante escrituras condicionales de S3. No requiere tabla DynamoDB.
- **Terraform 1.11:** `use_lockfile` pasa a ser estable (GA) y el argumento `dynamodb_table` queda **deprecado**. Según la documentación oficial del backend S3, el locking con DynamoDB se eliminará en una futura versión menor. Mientras tanto ambos mecanismos pueden configurarse a la vez para facilitar la migración.

Verificado en la [documentación oficial del backend S3](https://developer.hashicorp.com/terraform/language/backend/s3) y en el changelog de Terraform 1.11.

La decisión técnica del proyecto (`tech.md`) fija Terraform >= 1.10 con backend S3, `use_lockfile = true` y sin DynamoDB para locking.

## Opciones evaluadas

- **Opción A: DynamoDB para locking.** Mecanismo clásico y probado. Requiere una tabla adicional, tiene coste por operación y es el que Terraform ha deprecado.
- **Opción B: `use_lockfile = true`.** Locking nativo en S3. No añade recursos y es el sucesor oficial.

| Criterio | A: DynamoDB (`dynamodb_table`) | B: `use_lockfile = true` |
|---|---|---|
| Coste estimado | DynamoDB on-demand, aprox. 0,25 $ por millón de escrituras, más el mantenimiento de la tabla activa | Coste marginal de las escrituras/borrados de un objeto S3 pequeño; despreciable |
| Recursos AWS adicionales | 1 tabla DynamoDB (con su KMS, PITR e IAM asociados) | 0 (usa el bucket de estado existente) |
| Procedimiento de desbloqueo | `terraform force-unlock <LOCK_ID>` o borrar el ítem de bloqueo en la tabla DynamoDB | `terraform force-unlock <LOCK_ID>` o `aws s3 rm s3://<bucket>/<key>.tflock` |
| Estado de soporte | `dynamodb_table` **deprecado en Terraform 1.11**; se eliminará en una versión menor futura | Experimental en 1.10, GA desde 1.11; método recomendado oficialmente |

## Decisión

Se adopta la **Opción B**: `use_lockfile = true` en el bloque `backend "s3"`.

Terraform almacena el objeto de bloqueo `<key>.tflock` en el mismo bucket S3 que el archivo de estado y lo elimina al terminar la operación. No se crea ninguna tabla DynamoDB. Los roles de plan/apply deben tener permisos `s3:GetObject`, `s3:PutObject` y `s3:DeleteObject` sobre la clave `*.tflock` además de la del estado.

## Consecuencias

### Ventajas

1. **Coste cero de locking:** el coste de las operaciones de bloqueo es marginal y no hay tabla que facturar.
2. **Sin DynamoDB:** se elimina una dependencia y un recurso que gestionar, cifrar, respaldar y proteger con IAM.
3. **Soporte nativo:** S3 lo soporta desde Terraform 1.10 (GA en 1.11) y es la dirección oficial de HashiCorp, por lo que no habrá que migrar cuando se elimine `dynamodb_table`.

### Riesgos y mitigaciones

- **Lock huérfano:** si el proceso de Terraform termina de forma anormal (cancelación del job, caída de red, `kill`), el objeto `.tflock` persiste y bloquea las ejecuciones siguientes. Es el mismo riesgo que existía con DynamoDB.
- **Mitigación (desbloqueo manual).** Confirmar antes que no hay ninguna ejecución en curso y usar uno de estos procedimientos:
  1. `terraform force-unlock <LOCK_ID>`, con el `LOCK_ID` que muestra el mensaje de error "Error acquiring the state lock".
  2. Eliminar el objeto directamente: `aws s3 rm s3://<bucket>/<key>.tflock`.
- El `force-unlock` solo retira el guardián de coordinación; no repara el estado. Un desbloqueo con otra ejecución activa puede corromperlo.
- Los archivos `.tflock` no se versionan en Git (`.gitignore`), para evitar commits accidentales.
- El procedimiento se documenta también en el README del bootstrap.
- Se exige Terraform >= 1.10 (`required_version`), versión mínima que soporta `use_lockfile`.
