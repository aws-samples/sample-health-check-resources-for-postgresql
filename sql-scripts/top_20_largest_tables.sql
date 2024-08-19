SELECT
    schemaname AS schema_name,
    tablename AS table_name,
    pg_size_pretty(total_bytes) AS total_size,
    pg_size_pretty(table_bytes) AS table_size,
    pg_size_pretty(index_bytes) AS index_size,
    pg_size_pretty(COALESCE(toast_bytes, 0)) AS toast_size
FROM (
    SELECT *,
           total_bytes - index_bytes - COALESCE(toast_bytes, 0) AS table_bytes
    FROM (
           SELECT c.oid,
                  nspname AS schemaname,
                  relname AS tablename,
                  pg_total_relation_size(c.oid) AS total_bytes,
                  pg_indexes_size(c.oid) AS index_bytes,
                  pg_total_relation_size(c.reltoastrelid) AS toast_bytes
           FROM pg_class c
                    LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE c.relkind = 'r'
             AND n.nspname NOT IN ('information_schema', 'pg_catalog')
       ) a
) a
ORDER BY total_bytes DESC
LIMIT 20;
