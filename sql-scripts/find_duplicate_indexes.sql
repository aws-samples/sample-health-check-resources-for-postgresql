SELECT
    indrelid::regclass AS \"Associated Table Name\"
    ,array_agg(indexrelid::regclass) AS \"Duplicate Indexe Name\"
FROM pg_index
GROUP BY
    indrelid
    ,indkey
HAVING COUNT(*) > 1;
