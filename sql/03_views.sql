-- Lab QC & Operations Dashboard: analysis views
-- Five views that answer the lab's operational questions and feed the Tableau dashboard.
-- SIMULATED data (see README). Run after 01_schema.sql and 02_load.sql:
--   psql -d lab_qc -f sql/03_views.sql
-- Export each view to CSV for Tableau Public, for example:
--   \copy (SELECT * FROM v_backlog) TO 'data/exports/v_backlog.csv' WITH (FORMAT csv, HEADER true)


-- View 1: Turnaround time by assay ------------------------------------------
-- Question: How long does each test take from when the sample arrives to when
-- the result is reported, and are we hitting the turnaround target?
-- Counts only Final results that have a reported time.

CREATE OR REPLACE VIEW v_turnaround_by_assay AS
SELECT  s.assay_code,
        COUNT(r.reported_at) AS n_results,
        ROUND(AVG(EXTRACT(EPOCH FROM (r.reported_at - s.received_at)) / 3600)::numeric, 1) AS avg_tat_hours,
        a.target_tat_hours AS target_hours,
        ROUND(100.0 * AVG(CASE WHEN EXTRACT(EPOCH FROM (r.reported_at - s.received_at)) / 3600 <= a.target_tat_hours
                       THEN 1 ELSE 0 END), 1) AS pct_on_time
FROM samples s
JOIN results r ON s.sample_id = r.sample_id
JOIN assays a ON s.assay_code = a.assay_code
WHERE r.result_status = 'Final'
  AND r.reported_at IS NOT NULL
GROUP BY s.assay_code, a.target_tat_hours;


-- View 2: Backlog ----------------------------------------------------------
-- Question: What is waiting in the lab right now, and how long has it been waiting?
-- "Now" is fixed at the snapshot time 2026-11-13 18:00 (the end of the simulated data),
-- so the numbers do not change every time the view runs.

CREATE OR REPLACE VIEW v_backlog AS
SELECT  assay_code,
        status,
        COUNT(*) AS n_waiting,
        SUM(CASE WHEN priority = 'Rush' THEN 1 ELSE 0 END) AS n_rush,
        ROUND(AVG(EXTRACT(EPOCH FROM (TIMESTAMP '2026-11-13 18:00' - received_at)) / 3600)::numeric, 1) AS avg_age_hours,
        ROUND(MAX(EXTRACT(EPOCH FROM (TIMESTAMP '2026-11-13 18:00' - received_at)) / 3600)::numeric, 1) AS oldest_hours
FROM samples
WHERE status <> 'Reported'
GROUP BY assay_code, status;


-- View 3: Reruns and failures by station ------------------------------------
-- Question: Which instruments cause the most repeated or thrown-out work?
-- Failures (Invalidated results) are counted on the station where they happened,
-- not where the rework landed: QPCR-01 reran many of QPCR-02's failed samples,
-- so a rerun count alone points at the wrong instrument.

CREATE OR REPLACE VIEW v_rerun_by_station AS
SELECT  b.station_id,
        COUNT(*) AS n_results,
        SUM(CASE WHEN r.is_rerun THEN 1 ELSE 0 END) AS n_reruns,
        ROUND(100.0 * AVG(CASE WHEN r.is_rerun THEN 1 ELSE 0 END), 1) AS pct_rerun,
        SUM(CASE WHEN r.result_status = 'Invalidated' THEN 1 ELSE 0 END) AS n_invalidated,
        ROUND(100.0 * AVG(CASE WHEN r.result_status = 'Invalidated' THEN 1 ELSE 0 END), 1) AS pct_invalidated
FROM results r
JOIN batches b ON r.batch_id = b.batch_id
GROUP BY b.station_id;


-- View 4: QC control chart --------------------------------------------------
-- Question: Are the two qPCR instruments still measuring accurately, or is one drifting?
-- Uses the qPCR positive control (CTL-GX-POS).
--   baseline: September only (a period when both instruments were known to be fine),
--             mean +/- 2 standard deviations = control limits per station.
--             Limiting the baseline to the known-good period keeps the drift itself
--             from widening the limits.
--   runs:     every control run with a rolling average of the last 10 runs per station.
--   flag:     HIGH above the upper limit, LOW below the lower limit, otherwise OK.

CREATE OR REPLACE VIEW v_qc_control_chart AS
WITH baseline AS (
    SELECT  b.station_id,
            COUNT(*) AS n_runs,
            ROUND(AVG(qcr.measured_value), 3) AS baseline_mean,
            ROUND(STDDEV_SAMP(qcr.measured_value), 3) AS baseline_sd,
            ROUND(AVG(qcr.measured_value) + 2 * STDDEV_SAMP(qcr.measured_value), 3) AS upper_limit,
            ROUND(AVG(qcr.measured_value) - 2 * STDDEV_SAMP(qcr.measured_value), 3) AS lower_limit
    FROM qc_results qcr
    JOIN batches b ON qcr.batch_id = b.batch_id
    WHERE qcr.standard_id = 'CTL-GX-POS' AND qcr.measured_at < '2026-10-01'
    GROUP BY b.station_id
),
runs AS (
    SELECT  b.station_id,
            qcr.measured_at,
            qcr.measured_value,
            ROUND(AVG(qcr.measured_value) OVER (PARTITION BY b.station_id ORDER BY qcr.measured_at
                                                ROWS BETWEEN 9 PRECEDING AND CURRENT ROW), 2) AS rolling_avg_10
    FROM qc_results qcr
    JOIN batches b ON qcr.batch_id = b.batch_id
    WHERE qcr.standard_id = 'CTL-GX-POS'
)
SELECT  r.station_id,
        r.measured_at,
        r.measured_value,
        r.rolling_avg_10,
        bl.upper_limit,
        bl.lower_limit,
        CASE
            WHEN r.measured_value > bl.upper_limit THEN 'HIGH'
            WHEN r.measured_value < bl.lower_limit THEN 'LOW'
            ELSE 'OK'
        END AS flag
FROM runs r
JOIN baseline bl ON r.station_id = bl.station_id
ORDER BY r.station_id, r.measured_at;

-- Follow-up check: HIGH / LOW flags per station per month
-- SELECT  station_id,
--         TO_CHAR(measured_at, 'YYYY-MM') AS month,
--         COUNT(*) FILTER (WHERE flag = 'HIGH') AS n_high,
--         COUNT(*) FILTER (WHERE flag = 'LOW')  AS n_low,
--         COUNT(*) AS n_runs
-- FROM v_qc_control_chart
-- GROUP BY station_id, month
-- ORDER BY station_id, month;


-- View 5: Data quality checks -----------------------------------------------
-- Question: Before we trust this data in a dashboard, what is wrong with it?
-- Five checks stacked with UNION ALL, one row per check.

CREATE OR REPLACE VIEW v_data_quality AS

-- 1. Final results with no value
SELECT 'Missing Value On Final result' AS check_name,
        COUNT(*) AS n_issues
FROM results
WHERE value IS NULL AND result_status = 'Final'

UNION ALL

-- 2. Impossible negative values
SELECT 'Negative value', COUNT(*)
FROM results
WHERE value < 0

UNION ALL

-- 3. Result reported before the sample was received
SELECT 'Reported before received',
        COUNT(*)
FROM results r
JOIN samples s ON r.sample_id = s.sample_id
WHERE r.reported_at < s.received_at

UNION ALL

-- 4. More than one Final result for the same sample and batch
SELECT 'Duplicate Final result',
        COUNT(*)
FROM (
    SELECT  sample_id,
            batch_id,
            COUNT(*)
    FROM results
    WHERE result_status = 'Final'
    GROUP BY sample_id, batch_id
    HAVING COUNT(*) > 1
) d

UNION ALL

-- 5. Sample marked Reported but has no Final result
--    (the Final condition goes in the ON clause so the LEFT JOIN keeps samples with no match)
SELECT 'Reported with no result',
        COUNT(*)
FROM samples s
LEFT JOIN results r ON s.sample_id = r.sample_id AND r.result_status = 'Final'
WHERE s.status = 'Reported' AND r.result_id IS NULL;
