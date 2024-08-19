WITH index_stats AS (
    SELECT
        current_database() AS database_name,
        ns.nspname AS schema_name,
        ic.relname AS index_name,
        pg_size_pretty(pg_relation_size(ic.oid)) AS index_size,
        pg_relation_size(ic.oid) AS index_size_bytes,
        idx.indisunique AS is_unique,
        idx.indisprimary AS is_primary,
        COALESCE(NULLIF(pg_stat_user_indexes.idx_tup_read, 0), 0) AS estimated_row_count,
        (pg_relation_size(ic.oid)::bigint -
         COALESCE(
             NULLIF(pg_stat_user_indexes.idx_tup_read::bigint, 0) *
             NULLIF(pg_stat_user_indexes.idx_scan::bigint, 1),
             0
         )::bigint) AS estimated_bloat_bytes
    FROM pg_class ic
    JOIN pg_namespace ns ON ic.relnamespace = ns.oid
    JOIN pg_index idx ON ic.oid = idx.indexrelid
    JOIN pg_stat_user_indexes ON ic.oid = pg_stat_user_indexes.indexrelid
    WHERE ic.relkind = 'i'
      AND ns.nspname NOT IN ('information_schema', 'pg_catalog', 'pg_toast')
),
index_bloat AS (
    SELECT
        database_name,
        schema_name,
        index_name,
        CASE
            WHEN index_size_bytes > estimated_bloat_bytes THEN 'y'
            ELSE 'n'
        END AS can_estimate_bloat,
        estimated_row_count,
        pg_size_pretty(GREATEST(estimated_bloat_bytes, 0)) AS index_bloat_size,
        ROUND(
            100 *
            GREATEST(estimated_bloat_bytes::numeric, 0) / NULLIF(index_size_bytes::numeric, 0),
            2
        ) AS index_bloat_percent,
        pg_size_pretty(index_size_bytes) AS index_size
    FROM index_stats
)
SELECT
    database_name,
    schema_name,
    index_name,
    can_estimate_bloat,
    estimated_row_count,
    index_bloat_percent,
    index_bloat_size,
    index_size
FROM index_bloat
WHERE can_estimate_bloat='y'
ORDER BY schema_name, index_name;
