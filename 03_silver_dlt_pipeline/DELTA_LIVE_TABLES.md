# Delta Live Tables / Lakeflow pipelines — guía técnica (EuroBank)

> **Actualización de nombres (docs Oct 2026):** lo que se conocía como *Delta Live Tables (DLT)*
> hoy se llama **Apache Spark Declarative Pipelines (SDP)** + **Lakeflow pipelines** (extensión de SDP).
> Las docs viven en `docs.databricks.com/aws/en/ldp/`. En el proyecto conviven ambos nombres
> como sinónimos; el vigente es *Lakeflow pipelines*.

---

## 1. ¿Qué es?

Un framework **declarativo** para construir pipelines batch y streaming en SQL/Python.
En lugar de escribir código imperativo de orquestación (cuándo corre qué, reintentos,
estado), describes **qué** quieres producir y el motor resuelve el **cómo**.

- `https://docs.databricks.com/aws/en/ldp/` (Spark Declarative Pipelines on Lakeflow)
- `https://docs.databricks.com/aws/en/ldp/concepts/` (conceptos — actualizado13 Oct2026)

## 2. Arquitectura por debajo

```
┌─────────────────────────────────────────────────────────────────┐
│1. TU CÓDIGO declarativo (SQL/Python): tablas, vistas, flows     │
└──────────────────────────────┬──────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│2. CONTROL PLANE (Databricks)                                    │
│   • Analiza el código → construye el DAG de dependencias        │
│   • Planifica orden de ejecución + paralelismo máximo           │
│   • Reintentos progresivos: task → flow → pipeline completa     │
│   • Persiste el ESTADO de la pipeline (qué datos ya procesó)    │
│   • Modo de ejecución: triggered (procesa y para) o             │
│     continuous (queda viva)                                     │
└──────────────────────────────┬──────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│3. COMPUTE PLANE (Spark + Photon, DBR optimizado)                │
│   • Serverless o cluster clásico                                │
│   • Ejecuta los flows: leer fuente → transformar → escribir     │
│   • Incremental processing: solo reprocesa lo nuevo/cambiado    │
│     (escribes semántica de batch; el motor lo hace incremental) │
└──────────────────────────────┬──────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│4. ALMACENAMIENTO: tablas Delta en Unity Catalog                  │
│   • ACID, time travel, schema enforcement/evolution             │
│   • Predictive optimization: OPTIMIZE y VACUUM automáticos      │
│   • Estado incremental persistido en storage gestionado         │
└─────────────────────────────────────────────────────────────────┘
```

**Piezas clave:**

| Concepto | Qué es | Semántica |
|---|---|---|
| **Pipeline** | Unidad de desarrollo y ejecución (contenedor de todo) | Analiza dependencias y orquesta solo |
| **Flow** | Lee fuente → lógica → escribe destino | Append/Update (streaming) + *AUTO CDC* (SCD1/SCD2, exclusivo de Lakeflow) |
| **Streaming table** | Tabla Delta que es también target de streaming | Cada registro **exactamente1 vez** (fuentes append-only) |
| **Materialized view** | Tabla Delta de propósito batch | **Recomputa** el estado actual (joins, agregados, updates) |
| **View** | Intermedia, no persistida | Se evalúa al usar; barata para validaciones |
| **Expectations** | Regla booleana de calidad en cada dataset | `warn` / `drop` / `fail` según el registro |
| **Sink** | Destino de un flow | Delta, Kafka, EventHubs, custom Python |

## 3. Cómo funciona el ciclo

1. **Develop** — defines las tablas/vistas y sus flows en SQL/Python (notebooks o archivos)
2. **Publish/Validate** — el control plane valida esquemas, expectations y publica el plan (DAG)
3. **Run** — *triggered* (procesa lo disponible y termina — equivalente a `availableNow`)
   o *continuous* (viva — equivalente a `processingTime`)
4. **Incremental refresh** — al siguiente run solo lee lo nuevo; semántica de batch, ejecución incremental
5. **Publicación** — resultados como tablas UC consultables fuera de la pipeline
6. **Monitor** — calidad (expectations), linaje, métricas; `OPTIMIZE`/`VACUUM` automáticos
7. **Reintentos** — fallo transitorio: reintenta a nivel task, luego flow, luego pipeline

## 4. Aplicación en el proyecto EuroBank

| Requisito del sistema | Cómo lo cubre DLT/Lakeflow |
|---|---|
| Ingesta <15 min extremo a extremo | Auto Loader (bronze) → silver **incremental** → gold **MV**: solo deltas, sin reprocess completo |
| Calidad PCI-DSS/GDPR | **Expectations** como quality gates (`amount > 0`, `user_id IS NOT NULL`…) con política warn/drop/fail |
| Multicloud (S3 + ADLS + GCS) | Las3 tablas bronze (ya en UC sobre S3) son fuentes naturales de una pipeline de silver |
| Silver tipado (opción A del proyecto) | Los casts (`amount→double`, `timestamp→timestamp`, `flag→boolean`) declarados una vez y reprocesados idempotentemente |
| Orquestación silver→gold | **Automática**: el DAG de dependencias reemplaza orquestación manual |
| Right-to-be-forgotten <72 h | Delta ACID + `VACUUM` (predictive optimization) = borrado físico verificable; time travel para auditoría |
| Exactamente-una-vez | Estado en control plane = mismo principio que el checkpoint de Auto Loader, pero para toda la pipeline |
| Schema drift | Delta schema enforcement + expectations detectan cambios de esquema en silver |

 **Free tier:** verificar disponibilidad de pipelines en tu tier antes de comprometer el
diseño de `03_silver_dlt_pipeline`. Plan B: silver como notebook "DLT-style"
(mismas técnicas: casts, joins, expectations-análogas, `saveAsTable` overwrite) sin el motor
declarativo.

## 5. Importancia en la ingeniería de datos (por qué esto importa más allá del proyecto)

1. **Declarativo vs imperativo** — el código dice *qué*, no *cuándo/cómo correrlo*:
   cientos de líneas de Structured Streaming + orquestación manual se reducen a unas pocas
2. **Data quality como código** — expectations convierten las reglas de negocio en
   validaciones ejecutables en cada corrida (test-driven data)
3. **Orquestación integrada** — orden, paralelismo y reintentos sin pegarle a Airflow/Dagster
   (menos "glue code" frágil)
4. **Incremental y CDC sin boilerplate** — el motor resuelve estado, watermarks y hasta
   SCD Type1/2 (`AUTO CDC`) que en Structured Streaming puro es código a mano
5. **Mantenibilidad y CI/CD** — pipelines versionables, monitoreables (linaje, métricas) y
   con garantías Delta (ACID, time travel) de fábrica
6. **Equivalencia industrial** — dbt (transform declarativo) + Airflow (orquestación) +
   Spark Streaming (ejecución) bajo un solo marco gestionado
7. **Costo/rendimiento** — incremental processing + Photon + predictive optimization
   (OPTIMIZE/VACUUM) = menos compute desperdiciado que un `overwrite` nocturno completo

##6. Referencias (docs actuales)

- Qué es: https://docs.databricks.com/aws/en/ldp/
- Conceptos (datasets, flows, expectations): https://docs.databricks.com/aws/en/ldp/concepts/
- Calidad con expectations: https://docs.databricks.com/aws/en/ldp/expectations
- Modos triggered vs continuous: https://docs.databricks.com/aws/en/ldp/concepts/pipeline-mode
- Ingesta en pipelines (Auto Loader): https://docs.databricks.com/aws/en/ldp/load
- Límites/pipeline limitations: https://docs.databricks.com/aws/en/ldp/limitations
