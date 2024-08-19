#!/bin/bash

#Usage example
#./postgres_healthcheck.sh -h <DB_HOST> -p <DB_PORT> -d <DB_NAME> -U <DB_USER> -P <DB_PASSWORD> [--top-tables] [--duplicate-indexes] [--unused-indexes] [--bloat-analysis] [--log-prefix <PREFIX>] [--no-log] [--help]

# Function to display usage information
usage() {
  echo "Usage: $0 -h <DB_HOST> -p <DB_PORT> -d <DB_NAME> -U <DB_USER> -P <DB_PASSWORD> [--top-tables] [--duplicate-indexes] [--unused-indexes] [--bloat-analysis] [--log-prefix <PREFIX>] [--no-log] [--help]"
  echo
  echo "Options:"
  echo "  -h <DB_HOST>           Database host"
  echo "  -p <DB_PORT>           Database port"
  echo "  -d <DB_NAME>           Database name"
  echo "  -U <DB_USER>           Database user"
  echo "  -P <DB_PASSWORD>       Database password"
  echo "  --top-tables           Identify the top 20 largest tables"
  echo "  --duplicate-indexes    Identify duplicate indexes"
  echo "  --unused-indexes       Identify unused indexes"
  echo "  --bloat-analysis       Perform bloat analysis"
  echo "  --log-prefix <PREFIX>  Prefix for the log file"
  echo "  --no-log               Do not log output"
  echo "  --help                 Display this help message"
  exit 1
}

# Default log file behavior
LOG=true
LOG_PREFIX="postgres_healthcheck"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Parse input flags
while [[ $# -gt 0 ]]; do
  case $1 in
    -h)
      DB_HOST=$2
      shift 2
      ;;
    -p)
      DB_PORT=$2
      shift 2
      ;;
    -d)
      DB_NAME=$2
      shift 2
      ;;
    -U)
      DB_USER=$2
      shift 2
      ;;
    -P)
      DB_PASSWORD=$2
      shift 2
      ;;
    --top-tables)
      TOP_TABLES=true
      shift
      ;;
    --duplicate-indexes)
      DUPLICATE_INDEXES=true
      shift
      ;;
    --unused-indexes)
      UNUSED_INDEXES=true
      shift
      ;;
    --bloat-analysis)
      BLOAT_ANALYSIS=true
      shift
      ;;
    --log-prefix)
      LOG_PREFIX=$2
      shift 2
      ;;
    --no-log)
      LOG=false
      shift
      ;;
    --help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Ensure all required flags are provided
if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  usage
fi

# Setup logging
LOG_FILE="${LOG_PREFIX}_${TIMESTAMP}.log"
if [ "$LOG" = true ]; then
  exec > >(tee -i $LOG_FILE)
  exec 2>&1
fi

# Check PostgreSQL connection
echo "Checking PostgreSQL connection..."
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "\q"
if [ $? -ne 0 ]; then
  echo "Error: Unable to connect to the PostgreSQL database"
  exit 1
fi
echo "Connection successful."

# Function to execute a query
execute_query() {
  local query=$1
  PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "$query"
}

# Top 20 largest tables
if [ "$TOP_TABLES" = true ]; then
  echo "Identifying the top 20 largest tables..."
  execute_query "
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
  "
fi

# Duplicate indexes
if [ "$DUPLICATE_INDEXES" = true ]; then
  echo "Identifying duplicate indexes..."
  execute_query "
SELECT
    indrelid::regclass AS \"Associated Table Name\"
    ,array_agg(indexrelid::regclass) AS \"Duplicate Indexe Name\"
FROM pg_index
GROUP BY
    indrelid
    ,indkey
HAVING COUNT(*) > 1;
  "
fi

# Unused indexes
if [ "$UNUSED_INDEXES" = true ]; then
  echo "Identifying unused indexes..."
  execute_query "
  SELECT schemaname,
         relname AS table_name,
         indexrelname AS index_name,
         pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
         idx_scan AS index_scans
  FROM pg_stat_user_indexes ui
           JOIN pg_index i ON ui.indexrelid = i.indexrelid
  WHERE idx_scan < 1
    AND pg_relation_size(i.indexrelid) > 10240
  ORDER BY pg_relation_size(i.indexrelid) DESC;
  "
fi

# Table Bloat analysis
if [ "$BLOAT_ANALYSIS" = true ]; then
  echo "Performing Table bloat analysis..."
  execute_query "
WITH constants AS (
    -- define some constants for sizes of things
    -- for reference down the query and easy maintenance
    SELECT current_setting('block_size')::numeric AS bs, 23 AS hdr, 8 AS ma
),
no_stats AS (
    -- screen out table who have attributes
    -- which dont have stats, such as JSON
    SELECT table_schema, table_name,
        n_live_tup::numeric as est_rows,
        pg_table_size(relid)::numeric as table_size
    FROM information_schema.columns
        JOIN pg_stat_user_tables as psut
           ON table_schema = psut.schemaname
           AND table_name = psut.relname
        LEFT OUTER JOIN pg_stats
        ON table_schema = pg_stats.schemaname
            AND table_name = pg_stats.tablename
            AND column_name = attname
    WHERE attname IS NULL
        AND table_schema NOT IN ('pg_catalog', 'information_schema')
    GROUP BY table_schema, table_name, relid, n_live_tup
),
null_headers AS (
    -- calculate null header sizes
    -- omitting tables which dont have complete stats
    -- and attributes which aren't visible
    SELECT
        hdr+1+(sum(case when null_frac <> 0 THEN 1 else 0 END)/8) as nullhdr,
        SUM((1-null_frac)*avg_width) as datawidth,
        MAX(null_frac) as maxfracsum,
        schemaname,
        tablename,
        hdr, ma, bs
    FROM pg_stats CROSS JOIN constants
        LEFT OUTER JOIN no_stats
            ON schemaname = no_stats.table_schema
            AND tablename = no_stats.table_name
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        AND no_stats.table_name IS NULL
        AND EXISTS ( SELECT 1
            FROM information_schema.columns
                WHERE schemaname = columns.table_schema
                    AND tablename = columns.table_name )
    GROUP BY schemaname, tablename, hdr, ma, bs
),
data_headers AS (
    -- estimate header and row size
    SELECT
        ma, bs, hdr, schemaname, tablename,
        (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
        (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM null_headers
),
table_estimates AS (
    -- make estimates of how large the table should be
    -- based on row and page size
    SELECT schemaname, tablename, bs,
        reltuples::numeric as est_rows, relpages * bs as table_bytes,
    CEIL((reltuples*
            (datahdr + nullhdr2 + 4 + ma -
                (CASE WHEN datahdr%ma=0
                    THEN ma ELSE datahdr%ma END)
                )/(bs-20))) * bs AS expected_bytes,
        reltoastrelid
    FROM data_headers
        JOIN pg_class ON tablename = relname
        JOIN pg_namespace ON relnamespace = pg_namespace.oid
            AND schemaname = nspname
    WHERE pg_class.relkind = 'r'
),
estimates_with_toast AS (
    -- add in estimated TOAST table sizes
    -- estimate based on 4 toast tuples per page because we dont have
    -- anything better.  also append the no_data tables
    SELECT schemaname, tablename,
        TRUE as can_estimate,
        est_rows,
        table_bytes + ( coalesce(toast.relpages, 0) * bs ) as table_bytes,
        expected_bytes + ( ceil( coalesce(toast.reltuples, 0) / 4 ) * bs ) as expected_bytes
    FROM table_estimates LEFT OUTER JOIN pg_class as toast
        ON table_estimates.reltoastrelid = toast.oid
            AND toast.relkind = 't'
),
table_estimates_plus AS (
-- add some extra metadata to the table data
-- and calculations to be reused
-- including whether we cant estimate it
-- or whether we think it might be compressed
    SELECT current_database() as databasename,
            schemaname, tablename, can_estimate,
            est_rows,
            CASE WHEN table_bytes > 0
                THEN table_bytes::NUMERIC
                ELSE NULL::NUMERIC END
                AS table_bytes,
            CASE WHEN expected_bytes > 0
                THEN expected_bytes::NUMERIC
                ELSE NULL::NUMERIC END
                    AS expected_bytes,
            CASE WHEN expected_bytes > 0 AND table_bytes > 0
                AND expected_bytes <= table_bytes
                THEN (table_bytes - expected_bytes)::NUMERIC
                ELSE 0::NUMERIC END AS bloat_bytes
    FROM estimates_with_toast
    UNION ALL
    SELECT current_database() as databasename,
        table_schema, table_name, FALSE,
        est_rows, table_size,
        NULL::NUMERIC, NULL::NUMERIC
    FROM no_stats
),
bloat_data AS (
    -- do final math calculations and formatting
    select current_database() as databasename,
        schemaname, tablename, can_estimate,
        table_bytes, round(table_bytes/(1024^2)::NUMERIC,3) as table_mb,
        expected_bytes, round(expected_bytes/(1024^2)::NUMERIC,3) as expected_mb,
        round(bloat_bytes*100/table_bytes) as pct_bloat,
        round(bloat_bytes/(1024::NUMERIC^2),2) as mb_bloat,
        table_bytes, expected_bytes, est_rows
    FROM table_estimates_plus
)
-- filter output for bloated tables
SELECT databasename, schemaname, tablename,
    can_estimate,
    est_rows,
    pct_bloat, mb_bloat,
    table_mb
FROM bloat_data
-- this where clause defines which tables actually appear
-- in the bloat chart
-- example below filters for tables which are either 50%
-- bloated and more than 20mb in size, or more than 25%
-- bloated and more than 1GB in size
WHERE ( pct_bloat >= 50 AND mb_bloat >= 20 )
    OR ( pct_bloat >= 25 AND mb_bloat >= 1000 )
ORDER BY pct_bloat DESC;
  "
fi

# Index Bloat analysis
if [ "$BLOAT_ANALYSIS" = true ]; then
  echo "Performing Index bloat analysis..."
  execute_query "
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
  "
fi

echo "Health check complete."
