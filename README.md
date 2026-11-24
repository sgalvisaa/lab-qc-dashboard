# Lab QC & Operations Dashboard (SQL + Tableau)

**Live dashboard:** [Tableau Public](https://public.tableau.com/app/profile/stephanie.galvis/viz/LabQCOperationsDashboard/LabQCOperationsDashboard)

A lab operations and quality control dashboard for a genomics lab, built on **simulated** LIMS-style data. Five SQL views in PostgreSQL answer the questions a lab manager asks every week, and a Tableau dashboard shows the answers at a glance.

> **All data in this project is simulated.** It is modeled on the kind of data a LIMS or lab data warehouse holds (samples, batches, results, QC controls), with problems planted on purpose to test whether the SQL and the dashboard catch them. No real lab, patient, or client data is used.

## Questions the dashboard answers

| Question | SQL view | Dashboard element |
|---|---|---|
| Are we hitting turnaround targets for each test? | `v_turnaround_by_assay` | On-time KPI tile, on-time chart (Details) |
| What is waiting right now, and for how long? | `v_backlog` | Samples waiting tile, backlog heatmap |
| Which instruments cause the most failed or repeated work? | `v_rerun_by_station` | Failures vs. reruns chart (Details) |
| Is either qPCR instrument drifting out of control? | `v_qc_control_chart` | QC control chart, out-of-limit runs tile |
| Can we trust the data before we report it? | `v_data_quality` | Data quality tile and chart |

## Key findings

- **QPCR-02 drifted above its control limits in October.** 9 of its positive control runs were flagged HIGH (vs. 1 on QPCR-01). The 10-run rolling average shows the drift building before it peaks, which is the point of a control chart: catch the trend early, not after results fail.
- **Count failures where they happen, not where the rework lands.** QPCR-01 has the highest rerun rate (4.2%), but QPCR-02 has the highest failure rate (4.9%). QPCR-01 was rerunning QPCR-02's failed samples, so looking at reruns alone points at the wrong instrument.
- **In Progress is the bottleneck.** 69 samples are waiting. Received work is fresh (about 3 to 4 hours), while In Progress work is much older: NGS-Q30 averages 26 hours, and DNA-EXT has a 55-hour sample (over its 48-hour target) plus 3 rush samples.
- **Overall on-time rate is 89.0%.** NGS-Q30 is the best at 99.5%; the extractions (RNA-EXT 86.3%, DNA-EXT 87.1%) are the lowest.
- **The data quality checks found all 14 planted errors** across 5 checks before any number went on the dashboard.

## Metric definitions

| Metric | Definition |
|---|---|
| Turnaround time (TAT) | Hours from sample `received_at` to result `reported_at`, Final results only. |
| On-time % (per test) | Share of Final results with TAT at or under the test's target hours. |
| On-time rate (all tests) | Weighted by volume: `SUM(n_results * pct_on_time) / SUM(n_results)`, so busy tests count more than small ones. A plain average of the five percentages would overweight NGS-Q30 (208 results). |
| Samples waiting | Samples not yet Reported, as of the snapshot time 2026-11-13 18:00. |
| Average / oldest age | Hours each waiting sample has been in the lab since it was received, at the snapshot time. |
| Rerun % | Results flagged as reruns / all results, by station. |
| Failure % (invalidated) | Results with status Invalidated / all results, counted on the station that produced them. |
| Control limits | Per station: mean +/- 2 standard deviations of the positive control (CTL-GX-POS) during September, a period when both instruments were known to be working. |
| Rolling average | Average of the last 10 control runs per station (window function, `ROWS BETWEEN 9 PRECEDING AND CURRENT ROW`). |
| HIGH / LOW flag | A control run above the upper limit / below the lower limit. |

### Data quality checks (`v_data_quality`)

1. Final result with a missing value
2. Negative value (impossible for these measurements)
3. Result reported before the sample was received
4. More than one Final result for the same sample and batch
5. Sample marked Reported with no Final result (LEFT JOIN with the Final condition in the `ON` clause)

## Data model

Eight tables in PostgreSQL (`sql/01_schema.sql`):

- **Lookup tables:** `stations` (instruments), `analysts`, `assays` (tests, units, spec limits, turnaround targets), `qc_standards`
- **Activity tables:** `samples` (intake, priority, status), `batches` (which station ran which assay, when), `results` (one row per test attempt, including reruns and invalidated results), `qc_results` (control measurements per batch)

## Tools

PostgreSQL (CTEs, joins, CASE, window functions, `STDDEV_SAMP`, `UNION ALL`, views) · Tableau Public (dual axis, reference bands, calculated fields, heatmap, KPI tiles, filters) · Python (data generator)

## How to reproduce

```bash
createdb lab_qc
python scripts/generate_data.py                # writes the simulated CSVs to data/
psql -d lab_qc -f sql/01_schema.sql            # create tables
psql -d lab_qc -f sql/02_load.sql              # load the CSVs
psql -d lab_qc -f sql/03_views.sql             # create the 5 analysis views
```

Tableau Public cannot connect to a local database, so each view was exported to CSV (`data/exports/`) and the dashboard was built from those files.

## Repository structure

```
scripts/generate_data.py   simulated data generator
sql/01_schema.sql          tables and keys
sql/02_load.sql            load CSVs into PostgreSQL
sql/03_views.sql           the 5 analysis views
data/                      simulated source CSVs
data/exports/              view results used by Tableau
```

## Notes

- **My work:** I wrote all of the analysis SQL (the five views in `sql/03_views.sql`, including the data quality checks and the control chart logic), did the analysis, and designed and built the Tableau dashboard.
- **AI-assisted:** the simulated data and its planted problems (the QPCR-02 drift and 14 data quality errors) were generated with a Python script built with AI assistance (Claude), along with the setup scripts that create and load the tables (`sql/01_schema.sql`, `sql/02_load.sql`).
- Next steps: rebuild the dashboard in Power BI, and move the CSV-to-dashboard step to a cloud warehouse so the views refresh automatically instead of through manual exports.
