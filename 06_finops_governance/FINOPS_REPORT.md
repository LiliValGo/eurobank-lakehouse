# FinOps & Governance — Reporte de cierre (EuroBank Lakehouse)

> Objetivos FinOps del sistema: *"reducir costos60% vs. la solución anterior"* + *"gobernanza centralizada"*.
> Tres pilares: **VER** (observabilidad de costos) · **CONTROLAR** (presupuestos/alertas) ·
> **GOBERNAR** (grants, linaje, calidad).
> System tables: doc Oct2026 — https://docs.databricks.com/aws/en/admin/system-tables/

---

##0. Requisito previo — habilitar system tables (una vez)

```sql
-- Test: si responde, ya están habilitadas:
SELECT COUNT(*) FROM system.billing.usage;
```
- Si da error/vacío → Catalog Explorer → catálogo `system` → *Enable* (o seguir
  https://docs.databricks.com/aws/en/admin/system-tables/#enable-system-tables).
  Requisitos: workspace UC y permisos de administrador.
- Disponibilidad: `billing.usage` ~12 h de retardo; `query.history` ~1 h.
  En workspaces nuevos puede tardar más.

---

##1. CONTROLAR — Presupuestos (budgets)

### Ya implementado: Azure (Terraform en esta carpeta)
`main.tf` → `azurerm_consumption_budget_subscription`: **5 USD/mes** con4 alertas:

| Umbral | Tipo | Significado |
|---|---|---|
|50% | Actual | Aviso temprano (2.50 USD) |
|80% | Actual | Precaución (4.00 USD) |
|100% | Actual | Techo alcanzado |
|100% | **Forecasted** | Alerta *preventiva*: proyección de exceder a fin de mes |

### Equivalente en las otras nubes (para el contrato multicloud)
- **AWS Budgets**: https://aws.amazon.com/billing/budgets/ (alertas por costo/uso + forecast)
- **GCP Budgets**: https://cloud.google.com/billing/docs/how-to/budgets

### Databricks Free Tier (esta cuenta)
Cuota diaria de fair-use: si la excedes, **el compute se apaga el resto del día**
(datos intactos; ver
https://docs.databricks.com/en/getting-started/free-edition-limitations).
Eso YA es un presupuesto duro de fábrica — en tier de pago se sustituye por
*usage policies* / budget policies de serverless.

---

##2. VER — Costos y uso (system tables)

###2.1 Uso por día/producto (el corazón FinOps)
```sql
SELECT usage_date,
       billing_origin_product,          -- JOBS / DLT / SQL / INTERACTIVE / PREDICTIVE_OPTIMIZATION...
       sku_name,
       SUM(usage_quantity) AS consumo,
       usage_unit                       -- DBU, STORAGE_SPACE...
FROM system.billing.usage
GROUP BY ALL
ORDER BY usage_date DESC, consumo DESC;
```

###2.2 ¿En qué se va el consumo del último mes?
```sql
SELECT billing_origin_product,
       SUM(usage_quantity) AS consumo,
       usage_unit
FROM system.billing.usage
WHERE usage_date >= current_date() - 30
GROUP BY billing_origin_product
ORDER BY consumo DESC;
```
> Nota: `usage_quantity` está en **DBUs/unidades**, no en USD. Para USD, une con
> `system.billing.list_prices` (doc oficial con la query exacta:
> https://docs.databricks.com/aws/en/admin/usage/system-tables).

###2.3 Costos de predictive optimization (OPTIMIZE/VACUUM automáticos)
```sql
SELECT usage_date, SUM(usage_quantity) AS consumo
FROM system.billing.usage
WHERE billing_origin_product = 'PREDICTIVE_OPTIMIZATION'
GROUP BY ALL ORDER BY usage_date;
```

###2.4 Historial de queries — ¿qué consume y qué falla?
```sql
-- Top queries más lentas (7 días):
SELECT start_time, executed_by, statement_type, execution_status,
       total_duration_ms, waiting_for_compute_duration_ms, compute.type AS compute_type
FROM system.query.history
WHERE start_time >= current_timestamp() - INTERVAL 7 DAYS
ORDER BY total_duration_ms DESC
LIMIT 20;

-- Fallos recientes (útil para el troubleshooting del proyecto):
SELECT start_time, executed_by, statement_type, error_message
FROM system.query.history
WHERE execution_status = 'FAILED'
  AND start_time >= current_timestamp() - INTERVAL 7 DAYS
ORDER BY start_time DESC;
```
> `statement_text` aparece como `<REDACTED>` salvo account admin (free tier no tiene
> account console → asómelo — es *feature*, no bug: privacidad de queries).

---

##3. GOBERNAR — Auditoría de accesos

###3.1 Inventario de grants por catálogo (repítelo por cada catálogo)
```sql
-- Columnas REALES (doc Sep2026): table_catalog, table_schema, table_name,
-- grantee, grantor, privilege_type, is_grantable, inherited_from
SELECT table_catalog, table_schema, table_name, grantee, privilege_type, is_grantable
FROM eurobank_bronze.information_schema.table_privileges;
-- → eurobank_silver.information_schema.table_privileges
-- → eurobank_gold.information_schema.table_privileges
-- → eurobank_gdpr.information_schema.table_privileges
```
>  **Caveat de la doc:** `INFORMATION_SCHEMA` solo muestra grants **propios** (usuarios
> con `MANAGE` no ven los ajenos por esta vía). Para el inventario **completo** usa
> `SHOW GRANTS ON TABLE <tabla>` o Catalog Explorer (GUI).
> Doc: https://docs.databricks.com/aws/en/sql/language-manual/information-schema/table_privileges

*Gotcha del setup inicial:* los grants de UC usan **grupos de cuenta**
(`data_engineers`), no los grupos workspace-local creados con `CREATE GROUP`.

###3.2 Linaje (de dónde viene cada dato)
```sql
-- Primero mira las columnas (patrón seguro):
SELECT * FROM system.access.table_lineage LIMIT 10;
-- Luego filtra por tus tablas usando la columna de nombre de tabla que muestre DESCRIBE.
```

###3.3 Auditoría de eventos (quién hizo qué)
```sql
SELECT * FROM system.access.audit ORDER BY event_time DESC LIMIT 50;
```

###3.4 Calidad — expectations de la pipeline
- **UI**: Jobs & Pipelines → `eurobank_silver` → dataset → pestaña **Data quality**
  (5 expectations: `positive_amount` drop · `user_present` warn · `event_type_present` warn ·
  `valid_latitude`/`valid_longitude` drop)
- **SQL**: event log de pipelines (empieza por `SELECT * ... LIMIT5` + DESCRIBE):
  `system.lakeflow_pipeline_events_preview.pipeline_events`

###3.5 Linaje del proyecto (resumen arquitectónico)
```
S3 (Auto Loader) ─┐
ADLS (SDK SP) ────┼─► bronze (UC sobre S3) ─► pipeline eurobank_silver ─► gold
GCS (gcsfs) ──────┘        │                        │                        │
                     expectations              PII hasheada           KPIs BI/GDPR
                     (calidad PCI)              (GDPR art.17)         (vista360)
```

---

##4. HEALTH CHECK FINAL (capstone)
```sql
-- Inventario completo de filas por capa:
SELECT 'bronze_card' AS tabla, COUNT(*) AS filas FROM eurobank_bronze.raw.bronze_card_transactions
UNION ALL SELECT 'bronze_mobile', COUNT(*) FROM eurobank_bronze.raw.bronze_mobile_logs
UNION ALL SELECT 'bronze_geo',    COUNT(*) FROM eurobank_bronze.raw.bronze_geo_events
UNION ALL SELECT 'silver_card',   COUNT(*) FROM eurobank_silver.cleaned.silver_card_transactions
UNION ALL SELECT 'silver_mobile', COUNT(*) FROM eurobank_silver.cleaned.silver_mobile_logs
UNION ALL SELECT 'silver_geo',    COUNT(*) FROM eurobank_silver.cleaned.silver_geo_events
UNION ALL SELECT 'gold_spending', COUNT(*) FROM eurobank_gold.analytics.gold_user_spending
UNION ALL SELECT 'gold_cat',      COUNT(*) FROM eurobank_gold.analytics.gold_category_performance
UNION ALL SELECT 'gold_360',      COUNT(*) FROM eurobank_gold.analytics.gold_user_activity_360;

-- Evidencia GDPR:
SELECT * FROM eurobank_gdpr.audit.erasure_requests;
```

---

##5. Limitaciones de Free Tier (honestidad del reporte)
- Sin account console → sin retención configurable de system tables ni `statement_text`
- Sin SLA ni garantía de fiabilidad (doc oficial)
- Cuota diaria de compute (se apaga al excederla)
- Presupuestos Databricks: implícitos (la cuota); explícitos en Azure vía Terraform

##6. Links oficiales (docs verificadas Sep–Oct2026)
- System tables (referencia): https://docs.databricks.com/aws/en/admin/system-tables/
- billing.usage (esquema): https://docs.databricks.com/aws/en/admin/system-tables/billing
- query.history (esquema): https://docs.databricks.com/aws/en/admin/system-tables/query-history
- Monitor de costos (query USD): https://docs.databricks.com/aws/en/admin/usage/system-tables
- Free tier límites: https://docs.databricks.com/en/getting-started/free-edition-limitations
- VACUUM (GDPR): https://docs.databricks.com/aws/en/sql/language-manual/delta-vacuum
- Pipeline expectations: https://docs.databricks.com/aws/en/ldp/expectations
- TABLE_PRIVILEGES (esquema de grants): https://docs.databricks.com/aws/en/sql/language-manual/information-schema/table_privileges
