# Creating the ETL read-only role

Run this on an app server (reached through Systems Manager), as the master user. It needs a shell
where `DATABASE_URL` is set, and `psql` installed.

1. Set the password without showing it on screen or in shell history:

   ```bash
   read -rs ETL_PW && export ETL_PW
   ```

   Type the password and press Enter. Nothing appears while you type.

2. Run the file:

   ```bash
   psql "$DATABASE_URL" -v etl_password="$ETL_PW" -f create_etl_reader.sql
   ```

3. Clear the variable:

   ```bash
   unset ETL_PW
   ```

The secret `alphabridge/etl-db` must use the same password:
`{"username": "etl_reader", "password": "<the same password>"}`.

If `CREATE ROLE` says the role already exists, the role was created before. Then reset its password
with `ALTER ROLE etl_reader PASSWORD :'etl_password';` in the same way.
