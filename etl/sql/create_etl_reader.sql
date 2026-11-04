-- Creates the read-only role the ETL pipeline uses. Run it as the master user.
--
-- The password is not in this file. Pass it on the command line (see etl/sql/README.md):
--   psql "$DATABASE_URL" -v etl_password="$ETL_PW" -f create_etl_reader.sql
--
-- The role can only read the four tables the pipeline copies. It cannot write, and it
-- cannot see the API key tables.

CREATE ROLE etl_reader LOGIN PASSWORD :'etl_password';

GRANT CONNECT ON DATABASE postgres TO etl_reader;
GRANT USAGE ON SCHEMA public TO etl_reader;
GRANT SELECT ON transactions, refunds, cancellations, accounts TO etl_reader;
