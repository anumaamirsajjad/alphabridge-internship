# ETL pipeline: to-do list

Goal: move data from the `alphabridge` RDS Postgres into S3 (Bronze, Silver, Gold), query Gold through Athena views, and keep it reproducible through Terraform.

Status markers: `[x]` done, `[~]` in progress, `[ ]` not started, `[!]` needs a decision or approval from you.

---

## Phase 0: Discovery and decisions

- [x] Read the source schema (`db/migration/V1` to `V4`). Tables: `accounts`, `transactions`, `refunds`, `cancellations`, `idempotency_keys`, `operation_idempotency`, `api_clients`, `client_accounts`.
- [x] Confirm the engine and location (`infra/database.tf`): RDS PostgreSQL 18.3, `db.t4g.micro`, private subnet, `ap-south-1`, encrypted. The root `TODO.md` calls it "Aurora". Terraform is the source of truth, so this plan assumes RDS.
- [x] Check the state backend: S3 bucket `alphabridge-tfstate-169774886945` (already used by `infra/`).
- [x] Check how the app changes rows (`api/business/banking.py`). Findings below.
- [ ] `[!]` Confirm daily batch is enough (the default plan below). Real-time CDC would add a DMS instance and its cost.
- [ ] `[!]` Confirm the AWS account and region to deploy to. Default: the existing account `169774886945`, region `ap-south-1`.
- [ ] `[!]` Confirm who may run `terraform apply` for ETL resources. Default: the same pipeline role used for the API.

### What the code tells us (and why it changes the design)

| Table | Changes after insert? | Watermark for incremental load | Note |
|---|---|---|---|
| `transactions` | Yes: status, description, and version change | `updated_at` (set by cancel, refund, and PATCH) | Good. Incremental loads work. |
| `accounts` | Yes: `balance` changes on every transfer | **None.** No `updated_at` column. | Full reload each run is fine while the table is small. Daily balance history needs snapshots. |
| `refunds` | Inserted only, as far as the code shows | `created_at` | Append-only. |
| `cancellations` | Inserted only, as far as the code shows | `created_at` | Append-only. |
| `api_clients`, `client_accounts`, `idempotency_keys`, `operation_idempotency` | Not needed for analytics | Exclude from the pipeline | Security and internal data. Do not copy `key_hash` to the lake. |

- No `DELETE` statements exist in the app, so hard deletes are not a concern yet. Re-check this before go-live.
- `accounts` has no `updated_at`. Adding one needs a Flyway migration plus an app change. Decide in Phase 2 whether it's worth it.

---

## Phase 1: Local foundation (no AWS cost)

- [x] Create `etl/` folder layout:
  - [x] `etl/glue/lib/` shared logic (no AWS imports, so it is testable locally)
  - [x] `etl/glue/jobs/` Glue job entry points
  - [x] `etl/tests/` tests
  - [x] `etl/infra/` Terraform root module (Phase 2)
- [x] Bronze extract job for `transactions` (`etl/glue/jobs/bronze_extract.py`): JDBC read with the `updated_at` watermark and a 10-minute overlap; writes Parquet partitioned by `ingest_date`; a rerun on the same day replaces that day's partition
- [x] Silver transform for `transactions` (`etl/glue/lib/silver.py`, job `silver_transactions.py`): keeps the latest version per `transaction_id`, casts `amount` to DECIMAL(15,2), normalises currency and status
- [x] Unit tests: query builder (7 tests, run locally). Silver transform tests (2, PySpark) are skipped locally because there is no Java; they run in CI
- [x] CI job `etl-test` added to `.github/workflows/deploy-api.yml` (Java 17 + Python 3.12). Runs on develop and pull requests, like the API tests
- [ ] Silver tests have not run yet. First CI run on a pull request will confirm them.

## Phase 2: Infrastructure (Terraform in `etl/infra/`)

Written and validated (`terraform fmt` and `terraform validate` pass). Nothing is applied.

- [x] Separate Terraform root module in `etl/infra/`, with its own state key `alphabridge-etl/terraform.tfstate`
- [x] S3 buckets: bronze, silver, gold, scripts, and Athena results. Versioning, KMS encryption, public access blocked (`storage.tf`)
- [x] Lifecycle rules: Bronze to Glacier after 90 days; Athena results expire after 7 days (`storage.tf`)
- [x] Glue Data Catalog database `alphabridge_lake` (`glue.tf`)
- [x] Glue network connection and worker security group (`network.tf`)
- [x] Glue job role, Step Functions role, and scheduler role, each least-privilege (`iam.tf`)
- [x] Bronze and Silver Glue jobs (`glue.tf`)
- [x] Step Functions state machine: Bronze copy per table (max 2 at once) then Silver (`orchestration.tf`)
- [x] Daily EventBridge schedule at 19:30 UTC, after the backup window (`orchestration.tf`)
- [x] SNS topic and alarm on any failed pipeline run (`orchestration.tf`)
- [ ] `[!]` Blocked: plan cannot run. The IAM user `anum` gets AccessDenied on `secretsmanager:DescribeSecret` and `rds:DescribeDBInstances`. Needs read access, or a plan from the pipeline role.
- [x] Database name: `database_name` is now `postgres` (production, confirmed from the live Flyway output). `banking_db` was the local docker-compose name.
- [ ] `[!]` Create the secret `alphabridge/etl-db` by hand: `{"username": "etl_reader", "password": "..."}`. Terraform only looks up its ARN.
- [ ] `[!]` Create the read-only role on the database, as the master user, through an app server: `etl_reader`, with `CONNECT` on `postgres`, `USAGE` on `public`, and `SELECT` on `transactions`, `refunds`, `cancellations`, `accounts`. Use the same password as the secret.
- [x] Network endpoints written (`etl/infra/network.tf`): S3 gateway endpoint (free, adds a route to the main route table) and a Secrets Manager interface endpoint in one subnet (small monthly charge). Not applied.
- [ ] `[!]` Review the Secrets Manager endpoint's private DNS. It applies to the whole VPC, so the API servers also reach Secrets Manager through it. The endpoint's security group allows the whole VPC on 443 so the API keeps working. Confirm before apply.
- [ ] `[ ]` Glue job logs go to CloudWatch Logs, which needs its own endpoint or NAT. Not added. Check the first run's logs and add one only if it fails.
- [x] Database access (option A): `infra/security.tf` now has a conditional rule for 5432 from `alphabridge-etl-glue-sg`, controlled by `etl_access_enabled` (default `false`). The API deploy is unchanged until the flag is turned on.
- [ ] `[!]` Order of applies: apply `etl/infra` first, then set `etl_access_enabled = true` and apply `infra/`. Turning it on before the ETL network exists fails the API apply.
- [ ] `[!]` The `anum` IAM user gets 403 on the API's state object `alphabridge/terraform.tfstate`. Any plan or apply for either stack needs the pipeline role or wider read access.
- [ ] `[ ]` Watermark store: the schedule currently passes the epoch, so every run reads whole tables. Incremental runs need the last watermark saved (SSM Parameter Store or a DynamoDB table).
- [ ] `[ ]` Glue crawler or explicit table definitions, so Athena can query Silver (Phase 4).

## Phase 3: First end-to-end run (dev)

- [ ] Run the Bronze job for `transactions`; check the row count against `SELECT count(*) FROM transactions`
- [ ] Run the Silver job; check for duplicate `transaction_id` values (must be zero)
- [ ] Expand to `accounts` (full reload), `refunds`, and `cancellations`
- [ ] Reconciliation: row counts and `SUM(amount)` per day, source vs. Silver

## Phase 4: Gold layer

- [ ] Gold tables: `fact_transactions`, `dim_account`, `dim_date`, `agg_daily_transaction_summary`
- [ ] Define the grain and primary key of each table in writing before coding
- [ ] Athena views on top of the Gold tables (the business-facing names)
- [ ] `[!]` Decide if daily balance history is needed. If yes, add an `accounts` snapshot job, since `accounts` has no change history.

## Phase 5: Quality, monitoring, and handover

- [ ] Glue Data Quality rules: non-null keys, unique IDs, `amount > 0`, valid `status`, freshness
- [ ] Fail the workflow on critical rule failures
- [ ] CloudWatch alarms: job failures, no successful run in 26 hours, row-count drop beyond a threshold
- [ ] AWS Budgets alert for Glue and Athena spend
- [ ] Runbook: rerun, backfill, and recovering from a failed day
- [ ] Remove the ETL resources in the teardown list of the root `TODO.md` (section 8)

---

## Open questions for you

1. Daily batch is enough, or do you need near-real-time data? (Default: daily.)
2. Do you want daily balance history? (Default: no for now.)
3. Should ETL infra live in `etl/infra/` (recommended) or be added to `infra/`?
