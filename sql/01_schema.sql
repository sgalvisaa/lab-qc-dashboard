-- Lab QC & Operations Dashboard: schema
-- SIMULATED genomics lab data modeled on a LIMS / Benchling-style warehouse.
-- Run with: psql -d lab_qc -f sql/01_schema.sql

DROP TABLE IF EXISTS qc_results, results, batches, samples,
                     qc_standards, assays, analysts, stations CASCADE;

-- Lookup (dimension) tables -------------------------------------------

CREATE TABLE stations (
    station_id      TEXT PRIMARY KEY,          -- e.g. QPCR-01
    instrument_type TEXT NOT NULL,             -- Nucleic Acid Extractor, qPCR, NGS Sequencer
    location        TEXT NOT NULL
);

CREATE TABLE analysts (
    analyst_id  TEXT PRIMARY KEY,              -- e.g. AN-01
    initials    TEXT NOT NULL,
    role        TEXT NOT NULL,                 -- Research Associate I/II, Senior Scientist
    hired_on    DATE NOT NULL
);

CREATE TABLE assays (
    assay_code        TEXT PRIMARY KEY,        -- e.g. QPCR-GX
    assay_name        TEXT NOT NULL,
    instrument_type   TEXT NOT NULL,           -- which kind of station runs it
    units             TEXT NOT NULL,
    spec_low          NUMERIC,                 -- acceptance limits
    spec_high         NUMERIC,
    target_tat_hours  INTEGER NOT NULL         -- turnaround-time goal
);

CREATE TABLE qc_standards (
    standard_id    TEXT PRIMARY KEY,           -- e.g. CTL-GX-POS (positive control)
    assay_code     TEXT NOT NULL REFERENCES assays(assay_code),
    lot_number     TEXT NOT NULL,
    nominal_value  NUMERIC NOT NULL,           -- expected value of the control
    units          TEXT NOT NULL
);

-- Transaction (fact) tables ------------------------------------------

CREATE TABLE samples (
    sample_id     TEXT PRIMARY KEY,            -- e.g. S-2026-000123
    client        TEXT NOT NULL,
    sample_type   TEXT NOT NULL,               -- Blood, Tissue (FFPE), Cell Line, Saliva
    assay_code    TEXT NOT NULL REFERENCES assays(assay_code),
    priority      TEXT NOT NULL,               -- Routine, Rush
    received_at   TIMESTAMP NOT NULL,
    status        TEXT NOT NULL                -- Received, In Progress, Reported
);

CREATE TABLE batches (
    batch_id          TEXT PRIMARY KEY,        -- one instrument run (plate, extraction run, flow cell)
    station_id        TEXT NOT NULL REFERENCES stations(station_id),
    analyst_id        TEXT NOT NULL REFERENCES analysts(analyst_id),
    assay_code        TEXT NOT NULL REFERENCES assays(assay_code),
    run_started_at    TIMESTAMP NOT NULL,
    run_completed_at  TIMESTAMP
);

CREATE TABLE results (
    result_id     BIGINT PRIMARY KEY,
    sample_id     TEXT NOT NULL REFERENCES samples(sample_id),
    batch_id      TEXT NOT NULL REFERENCES batches(batch_id),
    value         NUMERIC,
    units         TEXT NOT NULL,
    is_rerun      BOOLEAN NOT NULL DEFAULT FALSE,
    rerun_reason  TEXT,                        -- QC fail, Instrument error, Out of spec confirm
    reported_at   TIMESTAMP,
    result_status TEXT NOT NULL                -- Final, Invalidated
);

CREATE TABLE qc_results (
    qc_id           BIGINT PRIMARY KEY,
    batch_id        TEXT NOT NULL REFERENCES batches(batch_id),
    standard_id     TEXT NOT NULL REFERENCES qc_standards(standard_id),
    measured_value  NUMERIC NOT NULL,
    measured_at     TIMESTAMP NOT NULL
);

-- Indexes on the columns we join and filter on most
CREATE INDEX idx_results_sample  ON results(sample_id);
CREATE INDEX idx_results_batch   ON results(batch_id);
CREATE INDEX idx_batches_station ON batches(station_id);
CREATE INDEX idx_qc_batch        ON qc_results(batch_id);
