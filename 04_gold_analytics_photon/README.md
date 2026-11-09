# Gold Analytics (Photon)

Las tablas de la capa **gold** se definen dentro de la misma pipeline declarativa que
silver — el motor de orquestación (Lakeflow/Databricks) resuelve automáticamente el DAG
`bronze → silver → gold`:

**Fuente de definiciones:** [`../03_silver_dlt_pipeline/eurobank_silver_pipeline.sql`](../03_silver_dlt_pipeline/eurobank_silver_pipeline.sql) — sentencias4-6.

| Tabla | Tipo | Contenido |
|---|---|---|
| `eurobank_gold.analytics.gold_user_spending` | materialized view | Gasto total, ticket medio y señales de fraude por usuario |
| `eurobank_gold.analytics.gold_category_performance` | materialized view | Volumen, ticket medio y tasa de decline por categoría/MCC |
| `eurobank_gold.analytics.gold_user_activity_360` | materialized view | Vista360 del usuario: transacciones (S3) + eventos móviles (ADLS) + geolocalización (GCS) |

**Rendimiento:** los agregados corren en serverless con **Photon** activo por defecto
(verificable: `SELECT product_features.is_photon FROM system.billing.usage`).
