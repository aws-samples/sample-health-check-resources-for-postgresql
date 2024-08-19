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
