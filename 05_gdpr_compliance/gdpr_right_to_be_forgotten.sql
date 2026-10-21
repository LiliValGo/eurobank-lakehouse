-- ============================================================
-- GDPR Right-to-be-forgotten — procedimiento de borrado eficaz
-- Titular: usr-1004 (marco.rossi@eurobank.com)
-- Alcance:8 tablas del lakehouse (bronze×3 · silver×3 · gold×2)
-- Fuera de alcance (anotado como límite): archivos crudos en
--   cloud storage (los gestiona el sistema productor) y el
--   contenido de _delta_log (VACUUM salta carpetas '_').
-- Docs: DELETE https://docs.databricks.com/aws/en/sql/language-manual/delta-delete-from
--       VACUUM https://docs.databricks.com/aws/en/sql/language-manual/delta-vacuum
--       Time travel https://docs.databricks.com/aws/en/tables/history
-- ============================================================

-- ------------------------------------------------------------
-- FASE0 — Auditoría (GDPR exige demostrar, no solo hacer)
-- ------------------------------------------------------------
CREATE CATALOG IF NOT EXISTS eurobank_gdpr;
CREATE SCHEMA IF NOT EXISTS eurobank_gdpr.audit;

CREATE TABLE IF NOT EXISTS eurobank_gdpr.audit.erasure_requests (
  request_id       STRING,
  subject_user_id  STRING,
  subject_email_hash STRING,
  requested_at     TIMESTAMP,
  completed_at     TIMESTAMP,
  status           STRING,      -- STARTED / COMPLETED
  tables_affected  INT,
  rows_deleted     INT,
  notes            STRING
) USING DELTA;

-- ------------------------------------------------------------
-- FASE1 — Identidad: la solicitud GDPR llega por EMAIL.
--   En bronze crudo el email existe; en silver solo su hash.
-- ------------------------------------------------------------
--1a. Email → user_id:
SELECT DISTINCT user_id
FROM eurobank_bronze.raw.bronze_mobile_logs
WHERE user_email = 'marco.rossi@eurobank.com';
-- → esperado: usr-1004

--1b. Email → el mismo hash que usa silver (para enlazar):
SELECT SHA2(LOWER('marco.rossi@eurobank.com'), 256) AS subject_email_hash;

-- ------------------------------------------------------------
-- FASE2 — Evidencia PREVIA + registro de la solicitud
--    ANTES de borrar, captura la versión actual (la5ª fase
--     la necesita para la evidencia de time travel):
-- ------------------------------------------------------------
--2a. Captura la versión (apunta el número de la PRIMERA fila):
DESCRIBE HISTORY eurobank_bronze.raw.bronze_mobile_logs;

--2b. Conteo previo en las8 tablas (temp view + foto):
CREATE OR REPLACE TEMP VIEW erasure_counts_before AS
SELECT 'bronze_card_transactions' AS tabla, COUNT(*) AS n
  FROM eurobank_bronze.raw.bronze_card_transactions   WHERE user_id = 'usr-1004'
UNION ALL SELECT 'bronze_mobile_logs',   COUNT(*)
  FROM eurobank_bronze.raw.bronze_mobile_logs         WHERE user_id = 'usr-1004'
UNION ALL SELECT 'bronze_geo_events',    COUNT(*)
  FROM eurobank_bronze.raw.bronze_geo_events          WHERE user_id = 'usr-1004'
UNION ALL SELECT 'silver_card_transactions', COUNT(*)
  FROM eurobank_silver.cleaned.silver_card_transactions WHERE user_id = 'usr-1004'
UNION ALL SELECT 'silver_mobile_logs',   COUNT(*)
  FROM eurobank_silver.cleaned.silver_mobile_logs     WHERE user_id = 'usr-1004'
UNION ALL SELECT 'silver_geo_events',    COUNT(*)
  FROM eurobank_silver.cleaned.silver_geo_events      WHERE user_id = 'usr-1004'
UNION ALL SELECT 'gold_user_spending',   COUNT(*)
  FROM eurobank_gold.analytics.gold_user_spending     WHERE user_id = 'usr-1004'
UNION ALL SELECT 'gold_user_activity_360', COUNT(*)
  FROM eurobank_gold.analytics.gold_user_activity_360 WHERE user_id = 'usr-1004';

SELECT * FROM erasure_counts_before;   -- ← guarda esta foto

--2c. Registrar la solicitud STARTED:
INSERT INTO eurobank_gdpr.audit.erasure_requests
  (request_id, subject_user_id, subject_email_hash, requested_at,
   completed_at, status, tables_affected, rows_deleted, notes)
SELECT
  'req-' || uuid(), 'usr-1004',
  SHA2(LOWER('marco.rossi@eurobank.com'), 256),
  current_timestamp(), NULL, 'STARTED', 8,
  (SELECT SUM(n) FROM erasure_counts_before),
  'GDPR art.17 right-to-be-forgotten';

-- ------------------------------------------------------------
-- FASE3 — Borrado
--   Regla: DELETE en tablas "de datos"; REFRESH en
--   materialized views (objetos derivados: se recalculan
--   desde sus fuentes YA sin el usuario).
--   La streaming table silver SÍ acepta DML (doc de UC lo
--   cita literalmente como caso de uso GDPR).
-- ------------------------------------------------------------
--3a. DELETE en datos (bronze×3 + silver streaming):
DELETE FROM eurobank_bronze.raw.bronze_card_transactions WHERE user_id = 'usr-1004';
DELETE FROM eurobank_bronze.raw.bronze_mobile_logs       WHERE user_id = 'usr-1004';
DELETE FROM eurobank_bronze.raw.bronze_geo_events        WHERE user_id = 'usr-1004';
DELETE FROM eurobank_silver.cleaned.silver_card_transactions WHERE user_id = 'usr-1004';

--3b. RECALCULAR las4 materialized views.
--     REFRESH manual NO está permitido en MVs de pipeline:
--       "Cannot REFRESH a Materialized View created from DLT,
--        instead update the Materialized View by starting the
--        DLT pipeline."
--    → Ve a Jobs & Pipelines → eurobank_silver → RUN y espera
--      a que termine en verde. El DAG recalcula las MVs desde
--      sus fuentes (ya sin usr-1004) — es el camino declarativo:
--      no se edita el derivado, se arregla el origen.

-- ------------------------------------------------------------
-- FASE4 — EVIDENCIA: el DELETE NO bastó (borrado lógico ≠ físico)
--   Usa el número de versión que capturaste en2a.
--    Delta BLOQUEA viajes a versiones más viejas que
--   delta.deletedFileRetentionDuration (default168 h =7 días):
--   error DELTA_UNSUPPORTED_TIME_TRAVEL_BEYOND_DELETED_FILE_RETENTION_DURATION
--   (falla rápido en vez de llevarte a archivos que VACUUM ya
--   pudo purgar). Nuestras versiones pre-DELETE tienen días →
--   ampliamos la ventana SOLO para la evidencia:
-- ------------------------------------------------------------
ALTER TABLE eurobank_bronze.raw.bronze_mobile_logs
  SET TBLPROPERTIES ('delta.deletedFileRetentionDuration' = '30 days');

-- EXPECTADO: ¡LOS DATOS SIGUEN AHÍ! (misma PII, versión vieja)
SELECT COUNT(*) AS filas_recuperables_version_vieja
FROM eurobank_bronze.raw.bronze_mobile_logs
VERSION AS OF <PON_AQUI_TU_VERSION>
WHERE user_id = 'usr-1004';

-- ------------------------------------------------------------
-- FASE5 — Borrado FÍSICO (VACUUM purga los Parquet viejos)
--   Retención por defecto =7 días → la bajamos a0 para
--   cumplir el SLA; Delta exige desactivar su safety check.
--   Docs: https://docs.databricks.com/aws/en/sql/language-manual/delta-vacuum
-- ------------------------------------------------------------
--  En serverless / SQL warehouse este conf NO existe en la allowlist
--   ([CONFIG_NOT_AVAILABLE.WITHOUT_SUGGESTION] — la allowlist de
--   configuraciones de Spark rechaza claves fuera de su registro).
--   Si el compute lo permitiera, la línea sería:
--     SET spark.databricks.delta.retentionDurationCheck.enabled = false;
--   Plan: ejecutar el VACUUM directo; si la safety check lo rechaza,
--   lanzar el VACUUM desde un notebook serverless (allowlist distinta).

ALTER TABLE eurobank_bronze.raw.bronze_card_transactions
  SET TBLPROPERTIES ('delta.deletedFileRetentionDuration' = '0 seconds');
ALTER TABLE eurobank_bronze.raw.bronze_mobile_logs
  SET TBLPROPERTIES ('delta.deletedFileRetentionDuration' = '0 seconds');
ALTER TABLE eurobank_bronze.raw.bronze_geo_events
  SET TBLPROPERTIES ('delta.deletedFileRetentionDuration' = '0 seconds');
ALTER TABLE eurobank_silver.cleaned.silver_card_transactions
  SET TBLPROPERTIES ('delta.deletedFileRetentionDuration' = '0 seconds');

VACUUM eurobank_bronze.raw.bronze_card_transactions;
VACUUM eurobank_bronze.raw.bronze_mobile_logs;
VACUUM eurobank_bronze.raw.bronze_geo_events;
VACUUM eurobank_silver.cleaned.silver_card_transactions;
-- Nota: las4 materialized views ya NO contienen al usuario
-- (se recalcularon); sus archivos históricos los purga
-- predictive optimization (VACUUM automático) de Databricks.

-- ------------------------------------------------------------
-- FASE6 — Verificación de eficacia
-- ------------------------------------------------------------
--6a. Foto POST: todo en0:
CREATE OR REPLACE TEMP VIEW erasure_counts_after AS
SELECT 'bronze_card_transactions' AS tabla, COUNT(*) AS n
  FROM eurobank_bronze.raw.bronze_card_transactions   WHERE user_id = 'usr-1004'
UNION ALL SELECT 'bronze_mobile_logs',   COUNT(*)
  FROM eurobank_bronze.raw.bronze_mobile_logs         WHERE user_id = 'usr-1004'
UNION ALL SELECT 'bronze_geo_events',    COUNT(*)
  FROM eurobank_bronze.raw.bronze_geo_events          WHERE user_id = 'usr-1004'
UNION ALL SELECT 'silver_card_transactions', COUNT(*)
  FROM eurobank_silver.cleaned.silver_card_transactions WHERE user_id = 'usr-1004'
UNION ALL SELECT 'silver_mobile_logs',   COUNT(*)
  FROM eurobank_silver.cleaned.silver_mobile_logs     WHERE user_id = 'usr-1004'
UNION ALL SELECT 'silver_geo_events',    COUNT(*)
  FROM eurobank_silver.cleaned.silver_geo_events      WHERE user_id = 'usr-1004'
UNION ALL SELECT 'gold_user_spending',   COUNT(*)
  FROM eurobank_gold.analytics.gold_user_spending     WHERE user_id = 'usr-1004'
UNION ALL SELECT 'gold_user_activity_360', COUNT(*)
  FROM eurobank_gold.analytics.gold_user_activity_360 WHERE user_id = 'usr-1004';

SELECT * FROM erasure_counts_after;    -- ←8 filas, todas n =0

--6b. Mismo viaje de la FASE4 — ahora debe FALLAR.
--     Subimos la ventana de nuevo para que el gate de retención
--     no tape el resultado: si el VACUUM purgó los Parquet, el
--     error es "file not found" = prueba de borrado FÍSICO real.
--     (Si NO subieras la ventana, el error sería el de retención
--     con0 — también bloquea, pero no prueba que los archivos
--     desaparecieron.)
ALTER TABLE eurobank_bronze.raw.bronze_mobile_logs
  SET TBLPROPERTIES ('delta.deletedFileRetentionDuration' = '30 days');

SELECT COUNT(*)
FROM eurobank_bronze.raw.bronze_mobile_logs
VERSION AS OF <PON_AQUI_TU_VERSION>
WHERE user_id = 'usr-1004';
-- EXPECTADO: error "cannot find / file not found ..." = ÉXITO

-- ------------------------------------------------------------
-- FASE7 — Cerrar la auditoría (SLA del sistema: <72 h)
-- ------------------------------------------------------------
UPDATE eurobank_gdpr.audit.erasure_requests
SET status = 'COMPLETED',
    completed_at = current_timestamp()
WHERE subject_user_id = 'usr-1004' AND status = 'STARTED';

SELECT request_id, subject_user_id, status, requested_at, completed_at,
       ROUND(unix_timestamp(completed_at) - unix_timestamp(requested_at), 0)
         AS duracion_segundos,
       rows_deleted, tables_affected, notes
FROM eurobank_gdpr.audit.erasure_requests
ORDER BY requested_at DESC;
