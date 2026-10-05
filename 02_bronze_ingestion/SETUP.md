# Configuración del Notebook Bronze - Azure ADLS Gen2

## Prerrequisitos

Antes de ejecutar el notebook, verifica que estos elementos existan:

| Elemento | Dónde verificar |
|----------|-----------------|
| Service Principal en Azure | Microsoft Entra ID → App registrations → `eurobank-databricks-sp` |
| Permisos en Storage Account | Storage Account `stkeurobankoyvixj` → IAM → Role assignments |
| Secret scope en Databricks | CLI: `databricks secrets list-scopes` (debe existir `eurobank-secrets`) |
| Schema en Unity Catalog | Catalog → `eurobank_bronze` → schemas |

---

## Paso 1: Secret scope y secretos en Databricks

El notebook lee **3 secretos** del scope `eurobank-secrets` con `dbutils.secrets.get`:
`azure-tenant-id`, `azure-client-id`, `azure-client-secret`.

> La UI antigua (*User Settings → Secrets*) fue retirada (docs Sep 2026); la vía oficial
> actual es la CLI. Crea el scope por URL `https://<workspace>#secrets/createScope` o con CLI:

```bash
# Login interactivo (OAuth en navegador, sin PAT)
databricks auth login --host https://<workspace>

# Scope + secretos (el valor se ingresa de forma interactiva, sin historial)
databricks secrets create-scope eurobank-secrets
databricks secrets put-secret eurobank-secrets azure-tenant-id      # valor: Tenant ID
databricks secrets put-secret eurobank-secrets azure-client-id      # valor: Application (client) ID
databricks secrets put-secret eurobank-secrets azure-client-secret  # valor: Client Secret (rotado)
```

---

## Paso 2: Verificar permisos del Service Principal en Azure

1. Ve a **Azure Portal** → **Storage Account** → `stkeurobankoyvixj`
2. Click en **Access Control (IAM)** → **Role assignments**
3. Verifica que `eurobank-databricks-sp` tenga el rol **Storage Blob Data Contributor**

Si no lo tiene:
1. Click en **Add** → **Add role assignment**
2. Rol: **Storage Blob Data Contributor**
3. Assign access to: **User, group, or service principal**
4. Selecciona: `eurobank-databricks-sp`
5. Click **Save**

---

## Paso 3: Verificar schema en Unity Catalog

Ejecuta en el SQL Editor:

```sql
-- Verificar que el schema existe
SHOW SCHEMAS IN eurobank_bronze;

-- Si no existe, crearlo
CREATE SCHEMA IF NOT EXISTS eurobank_bronze.raw;
```

---

## Paso 4: Ejecutar el notebook

1. Abre el notebook `Azure ADLS Gen2 - Serverless Compatible.ipynb`
2. Ejecuta las celdas en orden:
   - Celda 1: Instala el SDK (tarda ~30 segundos)
   - Celda 2: Configura credenciales (debe imprimir "Conectado a: stkeurobankoyvixj")
   - Celda 3: Lista archivos (debe mostrar los archivos en mobile/)
   - Celda 4: Ingesta a bronze.raw

---

## Paso 5: Verificar resultados

Ejecuta en el SQL Editor:

```sql
-- Verificar datos ingesta
SELECT COUNT(*) AS total_registros
FROM eurobank_bronze.raw.bronze_mobile_logs;

-- Ver muestra de datos
SELECT *
FROM eurobank_bronze.raw.bronze_mobile_logs
LIMIT 10;
```

---

## Solución de problemas

### Error: "Secret does not exist with scope"

Crea el secret como se describe en el Paso 1.

### Error: "Permission denied" o "Authentication failed"

Verifica que el Service Principal tenga el rol **Storage Blob Data Contributor** en el Storage Account (Paso 2).

### Error: "Table not found"

Crea el schema `eurobank_bronze.raw` como se describe en el Paso 3.

### Error: "ModuleNotFoundError"

Reinicia el kernel después de instalar los paquetes:
```python
dbutils.library.restartPython()
```
