# Unity Catalog + AWS S3 — Configuración verificada (EuroBank)

> Registro de la configuración **que funcionó** para conectar el bucket S3 de EuroBank a
> Databricks on AWS mediante Unity Catalog: **storage credential → external location →
> file events → grants → ingesta bronze**.
> Verificado con test de conexión **9/9 en verde** y `COUNT(*) = 150`.

---

## 0. Restricción arquitectónica (documentación vigente Sep 2026)

Un workspace de **Databricks on AWS** solo puede crear *storage credentials* + *external
locations* UC para **S3** (y Cloudflare R2 / DBFS root).

| Fuente | ¿External location UC desde AWS? | Alternativa |
|---|---|---|
| **AWS S3** | Sí (lectura/escritura) | — |
| Azure ADLS Gen2 | No (patrón legacy, *bypass* de UC) | SP + `spark.conf` → materializar en tablas UC sobre S3 |
| Google Cloud Storage | No (patrón legacy, *bypass* de UC) | Service account key + `spark.conf` → materializar en tablas UC sobre S3 |

Referencias:
- https://docs.databricks.com/aws/en/connect/unity-catalog/cloud-storage/
- https://docs.databricks.com/aws/en/connect/storage/azure-storage (legacy)
- https://docs.databricks.com/aws/en/connect/storage/gcs (legacy)

---

## 1. Inventario de recursos

| Recurso | Valor |
|---|---|
| AWS account | `123456789012` (placeholder — sustituye por el tuyo) |
| Región | `eu-west-1` (Irlanda) |
| Bucket S3 | `eurobank-raw-oyvixj` (versionado, acceso público bloqueado) |
| Prefijo | `s3://eurobank-raw-oyvixj/transactions/` |
| IAM role | `arn:aws:iam::123456789012:role/databricks-eurobank-s3-access` |
| IAM policy | `arn:aws:iam::123456789012:policy/databricks-eurobank-s3-policy` |
| UC Master Role (Databricks, no cambiar) | `arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL` |
| External ID de la credential | `11c1b0b7-a2e0-4c32-86a9-f4e6d5846060` |
| Storage credential (UC) | `eurobank_s3_location_awsiamrole_1789667147124` |
| External location (UC) | `eurobank_s3_location` → `s3://eurobank-raw-oyvixj/transactions` |
| Grupo de cuenta (UC) | `data_engineers` |
| Tabla bronze resultante | `eurobank_bronze.raw.bronze_card_transactions` (150 filas) |
| Credential sin uso (candidata a borrar) | `databricks-uc-7474645446433687-red_eurobank_storage` (creada por el setup automático) |

---

## 2. IAM — Trust policy del rol (self-assuming, obligatorio desde ene-2025)

AWS → IAM → Roles → `databricks-eurobank-s3-access` → **Trust relationships**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL",
          "arn:aws:iam::123456789012:role/databricks-eurobank-s3-access"
        ]
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "11c1b0b7-a2e0-4c32-86a9-f4e6d5846060"
        }
      }
    }
  ]
}
```

- Línea 1 del `Principal`: UC Master Role de Databricks.
- Línea 2: **ARN propio del rol** → sin esto, el check **Self Assume Role** falla con
  `INVALID_PARAMETER_VALUE: ... non self-assuming`.
- El `ExternalId` debe coincidir con el de la storage credential.

---

## 3. IAM — Permission policy del rol (la que funcionó completa)

AWS → IAM → `databricks-eurobank-s3-policy`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DatabricksS3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject", "s3:GetObjectVersion",
        "s3:PutObject", "s3:DeleteObject",
        "s3:ListBucket", "s3:GetBucketLocation",
        "s3:GetBucketAcl", "s3:PutObjectAcl",
        "s3:ListBucketMultipartUploads",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": [
        "arn:aws:s3:::eurobank-raw-oyvixj",
        "arn:aws:s3:::eurobank-raw-oyvixj/*"
      ]
    },
    {
      "Sid": "DatabricksSelfAssume",
      "Effect": "Allow",
      "Action": ["sts:AssumeRole"],
      "Resource": ["arn:aws:iam::123456789012:role/databricks-eurobank-s3-access"]
    },
    {
      "Sid": "ManagedFileEventsSetupStatement",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketNotification", "s3:PutBucketNotification",
        "sns:ListSubscriptionsByTopic", "sns:GetTopicAttributes",
        "sns:SetTopicAttributes", "sns:CreateTopic", "sns:TagResource",
        "sns:Publish", "sns:Subscribe",
        "sqs:CreateQueue", "sqs:DeleteMessage", "sqs:ReceiveMessage",
        "sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes",
        "sqs:SetQueueAttributes", "sqs:TagQueue",
        "sqs:ChangeMessageVisibility", "sqs:PurgeQueue"
      ],
      "Resource": [
        "arn:aws:s3:::eurobank-raw-oyvixj",
        "arn:aws:sqs:*:*:csms-*",
        "arn:aws:sns:*:*:csms-*"
      ]
    },
    {
      "Sid": "ManagedFileEventsListStatement",
      "Effect": "Allow",
      "Action": ["sqs:ListQueues", "sqs:ListQueueTags", "sns:ListTopics"],
      "Resource": "*"
    },
    {
      "Sid": "ManagedFileEventsTeardownStatement",
      "Effect": "Allow",
      "Action": ["sns:Unsubscribe", "sns:DeleteTopic", "sqs:DeleteQueue"],
      "Resource": ["arn:aws:sqs:*:*:csms-*", "arn:aws:sns:*:*:csms-*"]
    }
  ]
}
```

Notas:
- **Los 5 statements van juntos** en la misma policy (reemplazarla completa, no "pegar solo uno").
- `DatabricksSelfAssume` debe ir con el ARN **exacto** del rol — un `>` o placeholder
  (`<NOMBRE-DEL-ROL>`) invalida el statement en silencio.
- Multipart (`ListBucketMultipartUploads`, `ListMultipartUploadParts`, `AbortMultipartUpload`)
  necesario para archivos grandes.
- `List*` de SNS/SQS no soportan resource-level permissions → van con `Resource: "*"`.
- Los statements `ManagedFileEvents*` son los que permiten a Databricks crear los recursos
  `csms-*` (SNS topic + SQS queue) para **file events en modo Automatic**.

---

## 4. Databricks — Storage credential

Ruta UI: **Catalog → External Data → Credentials → Create credential**

1. Credential Type: **AWS IAM Role**
2. Name: `eurobank_s3_location_awsiamrole_1789667147124` (nombre generado por el flujo)
3. IAM Role ARN: `arn:aws:iam::123456789012:role/databricks-eurobank-s3-access`
4. Comment: `Card transactions from AWS S3`
5. **Create** → copiar el **External ID** mostrado (queda en el trust policy del paso 2)

**Validación (botón Validate Configuration)** — los 3 checks deben pasar:

```
Success - Assume Role
Success - Self Assume Role
Success - External ID Condition
```

---

## 5. Databricks — External location

Ruta UI: **Catalog → External Data → External Locations → Create external location**

| Campo | Valor |
|---|---|
| Name | `eurobank_s3_location` |
| Storage type | **S3** |
| URL | `s3://eurobank-raw-oyvixj/transactions/` |
| Storage credential | `eurobank_s3_location_awsiamrole_1789667147124` |
| Enable file events | PASS |
| File event type | **Automatic** |

**Test connection** — los 9 checks deben pasar:

```
PASS Read                    PASS Path Exists         PASS Assume Role
PASS List                    PASS File Events Read    PASS Self Assume Role
PASS Write                   (provisiona SNS/SQS   PASS External ID Condition
PASS Delete                   csms-* en eu-west-1)
```

### 5.1 Troubleshooting de File Events Read (lo que falló y se resolvió)

Error original:

```
File Events Read Failed
Provisioning has failed. Failed to provision file events resources:
Location could not be found. Please check your location and try again.
```

**Solución aplicada (en orden):**

1. **Corregir el ARN con `>` sobrante** en `DatabricksSelfAssume`
   (`...role/databricks-eurobank-s3-access>` → sin el `>`).
2. **Añadir los statements `ManagedFileEvents*`** (sección 3) a la permission policy del rol.
3. **Limpiar recursos huérfanos** de intentos fallidos:
   - SQS (eu-west-1) → borrar colas `csms-*`
   - SNS (eu-west-1) → borrar temas `csms-*`
   - S3 → `eurobank-raw-oyvixj` → Properties → Event notifications → borrar configs parciales
4. Re-ejecutar **Test connection** → 9/9 verdes.

**Si persiste:** borrar y recrear la external location (misma URL y credential, file events
Automatic). Todavía no hay tablas dependientes, es seguro. Útil recurso: CloudTrail
(Event history, eu-west-1) filtrando `CreateTopic` | `CreateQueue` |
`PutBucketNotificationConfiguration` para ver el `AccessDenied` exacto.

---

## 6. Grants (gobernanza)

**Nota clave:** `CREATE GROUP` crea un grupo **workspace-local**, que UC **no reconoce**:

> *"Workspace-local groups are not synchronized to the Databricks account and are not
> compatible with Unity Catalog."* → error `PRINCIPAL_DOES_NOT_EXIST.PRINCIPAL_DOES_NOT_EXIST`

**Crear el grupo a nivel de cuenta:** Account console (`accounts.cloud.databricks.com`) →
**User management → Groups → Create group** → `data_engineers` → añadir miembros.

*(Si quedó el grupo workspace-local: `DROP GROUP data_engineers;` antes de crear el de cuenta.)*

```sql
GRANT READ FILES, WRITE FILES, CREATE EXTERNAL TABLE
ON EXTERNAL LOCATION `eurobank_s3_location`
TO `data_engineers`;

SHOW GRANTS ON EXTERNAL LOCATION `eurobank_s3_location`;
```

Resultado esperado:

| Principal | ActionType |
|---|---|
| `data_engineers` | `CREATE EXTERNAL TABLE` |
| `data_engineers` | `READ FILES` |
| `data_engineers` | `WRITE FILES` |

---

## 7. Verificación funcional

```sql
DESCRIBE EXTERNAL LOCATION `eurobank_s3_location`;
-- name = eurobank_s3_location | url = s3://eurobank-raw-oyvixj/transactions
-- credential_name = eurobank_s3_location_awsiamrole_1789667147124

SHOW STORAGE CREDENTIALS;
SHOW EXTERNAL LOCATIONS;
```

```python
display(dbutils.fs.ls("s3://eurobank-raw-oyvixj/transactions/"))
```

**La ruta directa con `USING DELTA LOCATION` falla** si los archivos crudos no son Delta:

```
[DELTA_CREATE_EXTERNAL_TABLE_WITHOUT_TXN_LOG] ... there is no transaction log present at
`s3://eurobank-raw-oyvixj/transactions/_delta_log`
```

**Forma correcta (los archivos son un array JSON pretty-printed):**

```python
df = (spark.read
      .option("multiLine", "true")
      .option("mode", "PERMISSIVE")
      .json("s3://eurobank-raw-oyvixj/transactions/"))

df.write.mode("overwrite") \
  .option("mergeSchema", "true") \
  .saveAsTable("eurobank_bronze.raw.bronze_card_transactions")
```

```sql
SELECT COUNT(*) AS total_registros
FROM eurobank_bronze.raw.bronze_card_transactions;   -- 150
```

---

## 8. Checklist de diagnóstico rápido

| Check | SQL / acción | Esperado |
|---|---|---|
| Credential válida | UI → Validate Configuration | 3/3 verdes |
| Location válida | UI → Test connection | 9/9 verdes |
| Binding location↔credential | `DESCRIBE EXTERNAL LOCATION \`eurobank_s3_location\`` | credential `eurobank_s3_location_awsiamrole_1789667147124` |
| Grants | `SHOW GRANTS ON EXTERNAL LOCATION \`eurobank_s3_location\`` | 3 filas de `data_engineers` |
| Lectura | `dbutils.fs.ls("s3://eurobank-raw-oyvixj/transactions/")` | lista archivos |
| Datos | `SELECT COUNT(*) FROM eurobank_bronze.raw.bronze_card_transactions` | 150 |

---

## 9. Errores encontrados y solución (tabla resumen)

| Error | Causa | Solución |
|---|---|---|
| `Self Assume Role` falla (`INVALID_PARAMETER_VALUE ... non self-assuming`) | Trust policy sin el ARN propio del rol | Añadir el ARN del rol como principal + `sts:ExternalId` |
| `Read` falla tras editar policy | Se **reemplazó** la policy en vez de sumar statements | Restaurar la policy consolidada completa (sección 3) |
| `File Events Read` → `Location could not be found` | Recursos `csms-*` a medias + ARN con `>` | Limpiar SQS/SNS/bucket notifications + corregir ARN + recrear location |
| `PRINCIPAL_DOES_NOT_EXIST` en GRANT | Grupo creado con `CREATE GROUP` (workspace-local) | Crear grupo en Account console (nivel cuenta) |
| `DELTA_CREATE_EXTERNAL_TABLE_WITHOUT_TXN_LOG` | JSON crudo, no Delta, en la ruta | Leer JSON (`multiLine=true`) y `saveAsTable` |

---

## 10. Estado del sistema

- [x] **ADLS Gen2**: secret rotado al secret scope `eurobank-secrets` → SDK `azure-storage`
      → `eurobank_bronze.raw.bronze_mobile_logs` (notebook de `02_bronze_ingestion`).
- [x] **GCS**: service account key en secret scope → `gcsfs` → `eurobank_bronze.raw.bronze_geo_events`.
- [x] **Bronze Auto Loader** en *file notification mode* (JSONL + checkpoint en volumen UC)
      → `eurobank_bronze.raw.bronze_card_transactions`.
- [x] **Silver/Gold**: pipeline `eurobank_silver` (`03_silver_dlt_pipeline/`).
- [x] **GDPR**: procedimiento de borrado eficaz (`05_gdpr_compliance/`).
- [x] **FinOps**: system tables + presupuestos (`06_finops_governance/`).
- [ ] Limpieza: eliminar la credential sin uso
      `databricks-uc-7474645446433687-red_eurobank_storage`.
