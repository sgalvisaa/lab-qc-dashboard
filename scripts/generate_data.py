"""
Generate SIMULATED genomics lab operations data for the Lab QC & Operations
Dashboard.

The data imitates what a LIMS or lab data platform (Benchling-style warehouse)
holds for a biotech genomics lab: samples come in, scientists run them in
batches (DNA/RNA extraction, qPCR, NGS sequencing), every batch includes a QC
control, and results are reported.

Built into the data on purpose:
  1. A slow upward drift in the qPCR positive control Ct on instrument
     QPCR-02 (2026-10-05 to 2026-10-28), fixed by a service/calibration.
     Rising Ct means the instrument is losing sensitivity. A rolling-mean
     control chart should catch it before the hard QC limit does.
  2. A few data quality problems for the SQL checks to find in Session 2.

Output: CSV files in ../data/
Run:    python scripts/generate_data.py
"""

from datetime import date, datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

rng = np.random.default_rng(42)
OUT = Path(__file__).resolve().parent.parent / "data"
OUT.mkdir(exist_ok=True)

START = date(2026, 9, 1)
SNAPSHOT = datetime(2026, 11, 13, 18, 0)   # "today" for the warehouse extract
DRIFT_START = date(2026, 10, 5)
RECAL_DATE = date(2026, 10, 28)            # QPCR-02 serviced, offline that day
DRIFT_STATION = "QPCR-02"
DRIFT_PER_DAY = 0.035                      # Ct cycles per calendar day

# ---------------------------------------------------------------- lookups
stations = pd.DataFrame([
    ("EXT-01",  "Nucleic Acid Extractor", "Extraction Lab"),
    ("EXT-02",  "Nucleic Acid Extractor", "Extraction Lab"),
    ("QPCR-01", "qPCR",                   "Molecular Lab"),
    ("QPCR-02", "qPCR",                   "Molecular Lab"),
    ("SEQ-01",  "NGS Sequencer",          "Sequencing Core"),
], columns=["station_id", "instrument_type", "location"])

analysts = pd.DataFrame([
    ("AN-01", "JR", "Senior Scientist", "2019-03-11"),
    ("AN-02", "MP", "Research Associate II",     "2021-06-01"),
    ("AN-03", "KL", "Research Associate II",     "2022-01-17"),
    ("AN-04", "DS", "Research Associate I",      "2024-08-05"),
    ("AN-05", "TW", "Research Associate I",      "2025-02-24"),
    ("AN-06", "RB", "Research Associate I",      "2026-07-13"),
], columns=["analyst_id", "initials", "role", "hired_on"])

# assay_code, name, instrument, units, spec_low, spec_high, target_tat_hours,
# true mean, sd, samples per weekday
ASSAYS = [
    ("DNA-EXT", "DNA extraction yield",        "Nucleic Acid Extractor", "ng/uL", 10.0, 500.0,  48, 62.0, 18.0, 12),
    ("RNA-EXT", "RNA extraction yield",        "Nucleic Acid Extractor", "ng/uL",  5.0, 500.0,  48, 41.0, 13.0, 10),
    ("QPCR-GX", "qPCR gene expression (Ct)",   "qPCR",                   "Ct",    15.0,  35.0,  72, 26.0,  2.2, 12),
    ("QPCR-PT", "qPCR pathogen screen (Ct)",   "qPCR",                   "Ct",    15.0,  38.0,  72, 29.5,  2.6,  7),
    ("NGS-Q30", "NGS read quality (% >= Q30)", "NGS Sequencer",          "%",     80.0, 100.0, 120, 91.5,  3.0,  4),
]
assays = pd.DataFrame(
    [a[:7] for a in ASSAYS],
    columns=["assay_code", "assay_name", "instrument_type", "units",
             "spec_low", "spec_high", "target_tat_hours"])
A = {a[0]: dict(zip(["code", "name", "inst", "units", "lo", "hi", "tat",
                     "mean", "sd", "per_day"], a)) for a in ASSAYS}

# one certified reference standard per assay; qc sd is the normal run-to-run noise
QC = {
    "DNA-EXT": ("CTL-DNA-REF",  "L26-0412", 50.0, 3.0),   # reference cell line DNA
    "RNA-EXT": ("CTL-RNA-REF",  "L26-0419", 40.0, 2.5),   # reference RNA
    "QPCR-GX": ("CTL-GX-POS",   "L26-0533", 24.0, 0.25),  # positive control Ct
    "QPCR-PT": ("CTL-PT-POS",   "L26-0540", 27.0, 0.30),  # positive control Ct
    "NGS-Q30": ("CTL-PHIX",     "L26-0601", 93.0, 0.80),  # PhiX spike-in % >= Q30
}
qc_standards = pd.DataFrame(
    [(v[0], k, v[1], v[2], A[k]["units"]) for k, v in QC.items()],
    columns=["standard_id", "assay_code", "lot_number", "nominal_value", "units"])

# how long one run takes on each instrument type (min, max hours)
RUN_HOURS = {"Nucleic Acid Extractor": (1.5, 3.0), "qPCR": (1.5, 2.5),
             "NGS Sequencer": (24.0, 30.0)}

CLIENTS = ["Oncology Research", "Immunology", "Infectious Disease", "Partner Biotech", "Internal R&D"]
SAMPLE_TYPES = ["Blood", "Tissue (FFPE)", "Cell Line", "Saliva"]


def drift_bias(station_id, day):
    """Extra Ct on QPCR-02 while it drifts. Applies to controls and real samples."""
    if station_id == DRIFT_STATION and DRIFT_START <= day < RECAL_DATE:
        return DRIFT_PER_DAY * (day - DRIFT_START).days
    return 0.0


# ---------------------------------------------------------------- samples
days = pd.date_range(START, SNAPSHOT.date()).date
sample_rows = []
n = 0
for d in days:
    weekend = d.weekday() >= 5
    for code, a in A.items():
        count = rng.poisson(a["per_day"] * (0.15 if weekend else 1.0))
        for _ in range(count):
            n += 1
            hour = rng.uniform(7, 17)
            received = datetime.combine(d, datetime.min.time()) + timedelta(hours=hour)
            if received > SNAPSHOT:
                continue
            sample_rows.append({
                "sample_id": f"S-2026-{n:06d}",
                "client": rng.choice(CLIENTS, p=[0.3, 0.25, 0.2, 0.15, 0.1]),
                "sample_type": rng.choice(SAMPLE_TYPES, p=[0.35, 0.25, 0.3, 0.1]),
                "assay_code": code,
                "priority": "Rush" if rng.random() < 0.12 else "Routine",
                "received_at": received,
            })
samples = pd.DataFrame(sample_rows)

# ---------------------------------------------------------------- batches + results
# Simulate the queue: each workday, each station runs 1-2 batches of up to 10
# samples, Rush first, then oldest first.
inst_stations = stations.groupby("instrument_type")["station_id"].apply(list).to_dict()
analyst_ids = analysts["analyst_id"].tolist()

waiting = {code: [] for code in A}          # list of (priority_rank, received_at, sample_id, rerun_reason)
by_day = samples.groupby(samples["received_at"].dt.date)
batch_rows, result_rows, qc_rows = [], [], []
result_id = qc_id = batch_n = 0

for d in days:
    if d in by_day.groups:
        for s in by_day.get_group(d).itertuples():
            rank = 0 if s.priority == "Rush" else 1
            waiting[s.assay_code].append((rank, s.received_at, s.sample_id, None))
    if d.weekday() >= 5:
        continue

    for code, a in A.items():
        # alternate which station goes first so the work is shared
        slots = [(st, r) for r in range(2) for st in rng.permutation(inst_stations[a["inst"]])]
        for station, r in slots:
            if station == DRIFT_STATION and d == RECAL_DATE:
                continue                     # offline for recalibration
            if r == 1 and rng.random() < 0.45:
                continue                     # second run of the day only some days
            start = datetime.combine(d, datetime.min.time()) + timedelta(
                hours=8 + 4 * r + rng.uniform(0, 1.5))
            # only samples already received before the run starts
            ready = sorted([w for w in waiting[code] if w[1] < start])
            if not ready:
                continue
            take = ready[:6]
            for w in take:
                waiting[code].remove(w)

            batch_n += 1
            batch_id = f"B-{d:%y%m%d}-{batch_n:05d}"
            done = start + timedelta(hours=rng.uniform(*RUN_HOURS[a["inst"]]))
            batch_rows.append({
                "batch_id": batch_id, "station_id": station,
                "analyst_id": rng.choice(analyst_ids),
                "assay_code": code, "run_started_at": start,
                "run_completed_at": done,
            })

            # QC reference standard for this batch
            std_id, _, nominal, qc_sd = QC[code]
            bias = drift_bias(station, d) if a["inst"] == "qPCR" else 0.0
            qc_val = nominal + bias + rng.normal(0, qc_sd)
            qc_id += 1
            qc_rows.append({
                "qc_id": qc_id, "batch_id": batch_id, "standard_id": std_id,
                "measured_value": round(qc_val, 4),
                "measured_at": start + timedelta(minutes=20),
            })
            qc_fail = abs(qc_val - nominal) > 3 * qc_sd

            for (rank, rec, sid, prior_reason) in take:
                value = a["mean"] + bias + rng.normal(0, a["sd"])
                value = max(value, 0.5)  # yields and Ct values cannot be negative
                value = round(value, 3)
                review = timedelta(hours=float(rng.gamma(2.0, 6.0)))
                reported = done + review
                reason = None
                if qc_fail:
                    reason = "QC fail"
                elif rng.random() < 0.02:
                    reason = "Instrument error"
                elif prior_reason is None and not (a["lo"] <= value <= a["hi"]):
                    reason = "Out of spec confirm"

                result_id += 1
                result_rows.append({
                    "result_id": result_id, "sample_id": sid,
                    "batch_id": batch_id, "value": value,
                    "units": a["units"],
                    "is_rerun": prior_reason is not None,
                    "rerun_reason": prior_reason,
                    "reported_at": None if reason else (reported if reported <= SNAPSHOT else None),
                    "result_status": "Invalidated" if reason else "Final",
                })
                if reason:
                    waiting[code].append((0, rec, sid, reason))   # reruns jump the queue

results = pd.DataFrame(result_rows)
batches = pd.DataFrame(batch_rows)
qc_results = pd.DataFrame(qc_rows)

# ---------------------------------------------------------------- sample status at snapshot
final = results[(results.result_status == "Final") & results.reported_at.notna()]
in_batch = set(results.sample_id)
samples["status"] = np.where(
    samples.sample_id.isin(final.sample_id), "Reported",
    np.where(samples.sample_id.isin(in_batch), "In Progress", "Received"))

# ---------------------------------------------------------------- planted data quality issues
# (Session 2's SQL checks should find every one of these.)
fin_idx = results.index[(results.result_status == "Final") & results.reported_at.notna()]
pick = rng.choice(fin_idx, size=12, replace=False)

# a) 4 final results with a missing value
results.loc[pick[0:4], "value"] = np.nan
# b) 2 negative values (impossible for a purity or concentration)
results.loc[pick[4:6], "value"] = -results.loc[pick[4:6], "value"]
# c) 3 results reported before the sample was even received (bad timestamp entry)
for i in pick[6:9]:
    rec = samples.loc[samples.sample_id == results.at[i, "sample_id"], "received_at"].iloc[0]
    results.at[i, "reported_at"] = rec - timedelta(hours=int(rng.integers(5, 40)))
# d) 3 duplicate final results (same sample + batch entered twice)
dupes = results.loc[pick[9:12]].copy()
dupes["result_id"] = range(result_id + 1, result_id + 4)
results = pd.concat([results, dupes], ignore_index=True)
# e) 2 samples marked Reported that have no result at all
never_run = samples.index[samples.status == "Received"][:2]
samples.loc[never_run, "status"] = "Reported"

# ---------------------------------------------------------------- write CSVs
def write(df, name):
    df.to_csv(OUT / f"{name}.csv", index=False)
    print(f"{name:13s} {len(df):6,d} rows")

write(stations, "stations")
write(analysts, "analysts")
write(assays, "assays")
write(qc_standards, "qc_standards")
write(samples[["sample_id", "client", "sample_type", "assay_code",
               "priority", "received_at", "status"]], "samples")
write(batches, "batches")
results["result_id"] = results["result_id"].astype(int)
write(results, "results")
write(qc_results, "qc_results")
