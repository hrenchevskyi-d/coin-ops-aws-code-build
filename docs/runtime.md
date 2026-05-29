# Runtime SQL Operator Notes

The repository keeps only the database bootstrap assets needed by infrastructure:

- `deploy/sql/history/schema.sql`
- `deploy/sql/runtime/*.sql`

These files are consumed by VM Compose and k3s CNPG deployments. They are not application source.

## Postgres Image Requirements

PostgreSQL runtime mode requires:

- `pg_cron` for scheduled cleanup jobs
- `pgmq` for queue primitives

The image definition is `deploy/postgres-runtime/Dockerfile`, published as `coin-ops-postgres-runtime`. The server must start with `shared_preload_libraries = 'pg_cron'` and `cron.database_name` set to the application database name.

## Bootstrap Order

1. Apply the history schema from `deploy/sql/history/schema.sql`.
2. Set the application role GUC before loading runtime wrappers:

   ```sql
   ALTER DATABASE cognitor SET runtime.app_role = 'cognitor';
   ```

3. Apply runtime SQL from `deploy/sql/runtime`.

`deploy/sql/runtime/00_run_all.sql` includes sibling files from its working directory. Ansible and k3s run it from that staged runtime SQL directory.

## Operational Notes

- VM Compose deploy copies SQL to `/opt/cognitor/history` before starting backend services.
- k3s deploy creates a ConfigMap and runs a CNPG bootstrap Job.
- `RUNTIME_BACKEND=external` bypasses PostgreSQL queue/session primitives and is kept for rollback.
- Re-run the SQL bootstrap after runtime SQL changes as part of a controlled deployment, not as a standalone app migration flow.
