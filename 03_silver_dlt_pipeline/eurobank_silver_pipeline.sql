-- ============================================================
-- Pipeline: eurobank_silver (Lakeflow / Lakeflow pipelines)
-- Fuente:   eurobank_bronze.raw.* (3 nubes, datos crudos/string)
-- Destino:  eurobank_silver.cleaned.* (tipado, conformato, con calidad)
--           eurobank_gold.analytics.* (agregados de negocio)
-- Formato:  SQL (archivos .sql multi-sentencia separados por ';')
-- ============================================================

-- ------------------------------------------------------------
--1. TRANSACCIONES DE TARJETA (S3 → Auto Loader)
--    Fuente = streaming table append-only → target streaming table
--    con STREAM(...) para procesamiento incremental exactamente-1-vez
-- ------------------------------------------------------------
CREATE OR REFRESH STREAMING TABLE eurobank_silver.cleaned.silver_card_transactions (
  -- Calidad: importe imposible se DESCARTA (queda en métricas, no envenena agregados)
  CONSTRAINT positive_amount EXPECT (amount > 0) ON VIOLATION DROP ROW,
  -- Calidad: transacción sin usuario es sospechosa pero es dinero real → se CONSERVA + alerta (warn = default)
  CONSTRAINT user_present EXPECT (user_id IS NOT NULL)
)
AS SELECT
  transaction_id,
  user_id,
  CAST(`timestamp` AS TIMESTAMP)  AS `timestamp`,   -- string ISO → timestamp real (ventanas, SLA, particionado)
  CAST(amount AS DOUBLE)          AS amount,        -- bronze es string (opción A) → numérico para SUM/AVG
  currency,
  card_last_four,                                   -- PCI-DSS permite conservar los4 últimos
  card_type,
  merchant_name,
  merchant_category_code,
  category,
  status,
  auth_method,
  CAST(is_fraud_flag AS BOOLEAN) AS is_fraud_flag   -- "true"/"false" string → booleano real
FROM STREAM(eurobank_bronze.raw.bronze_card_transactions);

-- ------------------------------------------------------------
--2. LOGS MÓVILES (ADLS → SDK)
--    Fuente = Delta batch cargada con overwrite → materialized view
--    (recomputa el estado actual de la fuente)
--    PII: el email NUNCA pasa de aquí → solo hash (pseudonimización GDPR)
-- ------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW eurobank_silver.cleaned.silver_mobile_logs (
  -- Calidad: log sin tipo de evento = incompleto → conservar + alertar
  CONSTRAINT event_type_present EXPECT (event_type IS NOT NULL)
)
AS SELECT
  event_id,
  CAST(`timestamp` AS TIMESTAMP) AS `timestamp`,
  user_id,
  -- GDPR: hash SHA-256 del email. Downstream (gold/BI/ML) solo ve esto.
  SHA2(LOWER(user_email), 256)   AS user_email_hash,
  event_type,
  device_model,
  os_version,
  app_version,
  session_id,
  ip_address,
  `metadata`                     -- JSON-string llegado del patrón legacy ADLS
FROM eurobank_bronze.raw.bronze_mobile_logs;

-- ------------------------------------------------------------
--3. GEOLOCALIZACIÓN (GCS → gcsfs)
--    Fuente = Delta batch cargada con overwrite → materialized view
--    Coordenadas imposibles se DESCARTAN (romperían mapas y cálculos geo)
-- ------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW eurobank_silver.cleaned.silver_geo_events (
  CONSTRAINT valid_latitude  EXPECT (latitude BETWEEN -90 AND 90)  ON VIOLATION DROP ROW,
  CONSTRAINT valid_longitude EXPECT (longitude BETWEEN -180 AND 180) ON VIOLATION DROP ROW
)
AS SELECT
  geo_event_id,
  user_id,
  CAST(`timestamp` AS TIMESTAMP)     AS `timestamp`,
  CAST(latitude AS DOUBLE)           AS latitude,      -- string → double para haversine/distance
  CAST(longitude AS DOUBLE)          AS longitude,
  CAST(accuracy_meters AS DOUBLE)    AS accuracy_meters,
  city,
  country_code,
  timezone,
  connection_type,
  CAST(is_vpn_detected AS BOOLEAN)   AS is_vpn_detected
FROM eurobank_bronze.raw.bronze_geo_events;

-- ============================================================
-- CAPA GOLD — agregados de negocio (mismo pipeline: el DAG
-- ordena silver → gold automáticamente, respetando la cuota
-- free tier de1 pipeline activo)
-- Destino: eurobank_gold.analytics
-- ============================================================

-- ------------------------------------------------------------
--4. Gasto por usuario — KPI de negocio básico
-- ------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW eurobank_gold.analytics.gold_user_spending (
  -- Calidad sobre el agregado: un gasto total negativo sería imposible (warn)
  CONSTRAINT non_negative_spend EXPECT (total_spend >= 0)
)
AS SELECT
  user_id,
  COUNT(*)                                              AS tx_count,
  SUM(amount)                                           AS total_spend,
  AVG(amount)                                           AS avg_ticket,
  SUM(CASE WHEN is_fraud_flag THEN 1 ELSE 0 END)         AS fraud_suspects,
  MAX(`timestamp`)                                      AS last_tx_time
FROM eurobank_silver.cleaned.silver_card_transactions
GROUP BY user_id;

-- ------------------------------------------------------------
--5. Rendimiento por categoría — tasa de decline por MCC
-- ------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW eurobank_gold.analytics.gold_category_performance (
  -- Un rate fuera de [0,1] sería aritméticamente imposible → drop
  CONSTRAINT decline_rate_range EXPECT (decline_rate BETWEEN 0 AND 1) ON VIOLATION DROP ROW
)
AS SELECT
  category,
  merchant_category_code,
  COUNT(*)                                              AS tx_count,
  SUM(amount)                                           AS total_volume,
  AVG(amount)                                           AS avg_ticket,
  SUM(CASE WHEN status = 'DECLINED' THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS decline_rate
FROM eurobank_silver.cleaned.silver_card_transactions
GROUP BY category, merchant_category_code;

-- ------------------------------------------------------------
--6. Vista360 del usuario — el JOIN multicloud del lakehouse:
--    transacciones (S3) + logs móviles (ADLS) + geo (GCS)
--    Lee de gold_user_spending → el DAG encadena silver → gold → gold
-- ------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW eurobank_gold.analytics.gold_user_activity_360
AS SELECT
  s.user_id,
  s.total_spend,
  s.tx_count,
  s.avg_ticket,
  s.fraud_suspects,
  COALESCE(m.login_attempts, 0)                         AS login_attempts,
  COALESCE(m.total_events, 0)                           AS total_mobile_events,
  COALESCE(g.cities_visited, 0)                         AS cities_visited,
  COALESCE(g.countries_visited, 0)                      AS countries_visited,
  g.last_geo_seen
FROM eurobank_gold.analytics.gold_user_spending s
LEFT JOIN (
  SELECT
    user_id,
    COUNT(*) AS total_events,
    SUM(CASE WHEN event_type IN ('LOGIN_SUCCESS', 'LOGIN_FAILED') THEN 1 ELSE 0 END) AS login_attempts
  FROM eurobank_silver.cleaned.silver_mobile_logs
  GROUP BY user_id
) m ON s.user_id = m.user_id
LEFT JOIN (
  SELECT
    user_id,
    COUNT(DISTINCT city)          AS cities_visited,
    COUNT(DISTINCT country_code)  AS countries_visited,
    MAX(`timestamp`)              AS last_geo_seen
  FROM eurobank_silver.cleaned.silver_geo_events
  GROUP BY user_id
) g ON s.user_id = g.user_id;
