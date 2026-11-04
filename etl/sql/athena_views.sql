-- Business views for reports. They sit on top of the Gold tables in database alphabridge_lake.
-- Run in the Athena workgroup alphabridge-etl. Each statement can be run again safely
-- (CREATE OR REPLACE), so the views can be recreated at any time.
--
-- Views are created with SQL, not Terraform, so people can edit a view here without touching
-- infrastructure. Run each statement separately.

CREATE OR REPLACE VIEW v_transactions AS
SELECT
  transaction_id,
  from_account_id,
  to_account_id,
  amount,
  currency,
  status,
  created_at,
  transaction_date
FROM gold_fact_transactions;

CREATE OR REPLACE VIEW v_daily_transaction_summary AS
SELECT
  transaction_date,
  status,
  transaction_count,
  total_amount
FROM gold_agg_daily_transaction_summary;

-- Accounts without the account holder's name (personal data is not in Gold).
CREATE OR REPLACE VIEW v_accounts AS
SELECT
  account_id,
  currency,
  created_at
FROM gold_dim_account;
