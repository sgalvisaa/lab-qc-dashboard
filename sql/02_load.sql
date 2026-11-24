-- Load the generated CSVs into the tables.
-- Run from the project folder: psql -d lab_qc -f sql/02_load.sql
-- Order matters: lookup tables first, because the fact tables reference them.

\copy stations     FROM 'data/stations.csv'     WITH (FORMAT csv, HEADER true)
\copy analysts     FROM 'data/analysts.csv'     WITH (FORMAT csv, HEADER true)
\copy assays       FROM 'data/assays.csv'       WITH (FORMAT csv, HEADER true)
\copy qc_standards FROM 'data/qc_standards.csv' WITH (FORMAT csv, HEADER true)
\copy samples      FROM 'data/samples.csv'      WITH (FORMAT csv, HEADER true)
\copy batches      FROM 'data/batches.csv'      WITH (FORMAT csv, HEADER true)
\copy results      FROM 'data/results.csv'      WITH (FORMAT csv, HEADER true)
\copy qc_results   FROM 'data/qc_results.csv'   WITH (FORMAT csv, HEADER true)

-- Quick row-count check
SELECT 'stations' AS table_name, COUNT(*) FROM stations
UNION ALL SELECT 'analysts',     COUNT(*) FROM analysts
UNION ALL SELECT 'assays',       COUNT(*) FROM assays
UNION ALL SELECT 'qc_standards', COUNT(*) FROM qc_standards
UNION ALL SELECT 'samples',      COUNT(*) FROM samples
UNION ALL SELECT 'batches',      COUNT(*) FROM batches
UNION ALL SELECT 'results',      COUNT(*) FROM results
UNION ALL SELECT 'qc_results',   COUNT(*) FROM qc_results;
