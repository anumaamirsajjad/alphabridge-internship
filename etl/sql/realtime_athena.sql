-- Athena tables and views for the real-time transfer events.
-- The Lambda (realtime/lambda/handler.py) writes JSON-lines files to
-- s3://alphabridge-lake-gold-169774886945/realtime/transactions/dt=YYYY-MM-DD/hour=HH/
--
-- Partition projection: Athena works out the dt and hour folders itself, so no crawler or
-- MSCK REPAIR is needed when new hours appear.
--
-- Run each statement separately, in the workgroup alphabridge-etl, database alphabridge_lake.
-- Each statement can be run again safely.

CREATE EXTERNAL TABLE IF NOT EXISTS realtime_transactions (
  event_id      string,
  event_type    string,
  txn_id        string,
  from_account  string,
  to_account    string,
  amount        string,
  currency      string,
  status        string,
  event_time    string,
  is_large      boolean,
  processed_at  string
)
PARTITIONED BY (dt string, hour string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://alphabridge-lake-gold-169774886945/realtime/transactions/'
TBLPROPERTIES (
  'projection.enabled'      = 'true',
  'projection.dt.type'      = 'date',
  'projection.dt.format'    = 'yyyy-MM-dd',
  'projection.dt.range'     = '2026-01-01,NOW',
  'projection.hour.type'    = 'integer',
  'projection.hour.range'   = '0,23',
  'projection.hour.digits'  = '2',
  'storage.location.template' = 's3://alphabridge-lake-gold-169774886945/realtime/transactions/dt=${dt}/hour=${hour}/'
);

-- The same event can be written twice (SQS delivers at least once). This view keeps one row per
-- event_id, the copy that was processed last. Reports should read this view, not the table.
CREATE OR REPLACE VIEW v_realtime_transactions AS
SELECT
  txn_id,
  from_account,
  to_account,
  CAST(amount AS DECIMAL(15,2)) AS amount,
  currency,
  status,
  CAST(from_iso8601_timestamp(event_time) AS TIMESTAMP) AS event_time,
  is_large,
  CAST(from_iso8601_timestamp(processed_at) AS TIMESTAMP) AS processed_at
FROM (
  SELECT
    *,
    row_number() OVER (PARTITION BY event_id ORDER BY processed_at DESC) AS copy_number
  FROM realtime_transactions
)
WHERE copy_number = 1;
