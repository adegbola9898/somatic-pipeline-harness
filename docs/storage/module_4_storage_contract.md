# Module 4 — Cloud Storage Contract

## Objective

Define the storage layout and upload contract for pipeline runs in cloud object storage.

This module establishes the canonical mapping between:

local pipeline execution layout

and

cloud object storage layout used by the API and dashboard.

This contract ensures the pipeline can remain execution-oriented locally while cloud storage remains consumer-oriented.

---

# Cloud Run Root

Every pipeline run must upload artifacts to:

gs://<bucket>/runs/<run_id>/

No artifact for a run may exist outside this prefix.

---

# Cloud Storage Layout

The canonical cloud structure is:

gs://<bucket>/runs/<run_id>/
│
├── metadata/
├── logs/
├── reports/
├── outputs/
└── qc/

These categories are fixed for v1.

---

# Category Responsibilities

metadata  
Run contract and lifecycle state.

logs  
stdout and stderr logs for the run.

reports  
Human-readable review outputs and variant summaries.

outputs  
Core pipeline outputs such as BAM and VCF files.

qc  
Coverage metrics and QC gate results used by the dashboard.

---

# Metadata-First Discovery

The API and dashboard must discover run state and available artifacts using:

metadata/status.json  
metadata/artifacts.json

The API must **not scan the bucket** to determine what artifacts exist.

Bucket objects support retrieval only.

Metadata is the source of truth.

---

# Upload Scope

## Required Uploads

metadata/
run_manifest.json  
status.json  
artifacts.json  

logs/
<SAMPLE>.stdout.log  
<SAMPLE>.stderr.log  

reports/
<SAMPLE>.report.html  
<SAMPLE>.PASS.annotated.tsv  
<SAMPLE>.gene_summary.tsv  
<SAMPLE>.PASS.flagged.tsv  
<SAMPLE>.PASS.somaticish.tsv  
<SAMPLE>.PASS.germlineish.tsv  
<SAMPLE>.PASS.uncertain.tsv  

qc/
coverage_summary.tsv  
per_gene_coverage.tsv  
qc_gate.tsv  
<SAMPLE>.flagstat.txt  

outputs/
bam/<SAMPLE>.sorted.markdup.bam  
bam/<SAMPLE>.sorted.markdup.bam.bai  

mutect2/*.vcf.gz  

---

# Optional Uploads

Optional artifacts may include:

mutect2/*.f1r2.tar.gz  
mutect2/read-orientation-model.tar.gz  

Additional analysis files may also be uploaded if they follow the category layout.

---

# Excluded from Upload

The following directories must not be uploaded:

runs/<run_id>/inputs/  
runs/<run_id>/work/  

These are execution-local directories.

They contain temporary or intermediate files and are not part of the product storage contract.

---

# Naming Invariants

All uploaded objects must follow these rules.

1. Run-root invariant

All artifacts live under:

runs/<run_id>/

2. Category invariant

Top-level folders are fixed:

metadata  
logs  
reports  
outputs  
qc  

3. Filename preservation

Local filenames must be preserved in cloud storage.

Example:

SAMPLE.report.html  
remains  

reports/SAMPLE.report.html

4. Deterministic paths

Uploads must not append timestamps, UUIDs, or random identifiers to filenames.

Paths must remain deterministic.

---

# Upload Policy

## Successful Runs

Upload:

metadata  
logs  
reports  
qc  
outputs  

Optional artifacts may also be uploaded.

A run is considered cloud-complete when all required artifacts for successful runs are present.

---

## Failed Runs

Upload at minimum:

metadata/run_manifest.json  
metadata/status.json  
logs/stdout  
logs/stderr  

Reports, QC files, and outputs are not required if the run terminated before they were produced.

---

# Worked Example

Run:

run_metadata_smoke_001

Sample:

DEMO1

Cloud layout:

gs://bucket/runs/run_metadata_smoke_001/

metadata/
run_manifest.json  
status.json  
artifacts.json  

logs/
DEMO1.stdout.log  
DEMO1.stderr.log  

reports/
DEMO1.report.html  
DEMO1.PASS.annotated.tsv  
DEMO1.gene_summary.tsv  

qc/
coverage_summary.tsv  
per_gene_coverage.tsv  
qc_gate.tsv  

outputs/
bam/DEMO1.sorted.markdup.bam  
bam/DEMO1.sorted.markdup.bam.bai  

mutect2/DEMO1.filtered.vcf.gz  

---

# Module Completion Criteria

Module 4 is complete when:

• cloud storage layout is defined  
• required artifact uploads are defined  
• optional artifacts are defined  
• excluded artifacts are defined  
• naming invariants are defined  
• upload success/failure policy is defined  

---

# Go / No-Go

Proceed to the next module only if:

the cloud layout is accepted as the stable v1 storage contract

and

API development can rely entirely on metadata-based artifact discovery.
