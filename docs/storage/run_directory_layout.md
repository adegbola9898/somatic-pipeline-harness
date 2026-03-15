# Run Directory Layout

## Purpose

This document defines the canonical directory layout for a pipeline run.

The goal is to ensure that:

- pipeline outputs are predictable  
- metadata is machine-readable  
- cloud storage layout is stable  
- the backend API can locate artifacts reliably  

This layout must remain stable across pipeline versions.

---

# Canonical Run Root

Each pipeline execution is represented by a unique `run_id`.

All outputs for that run are stored under a run-scoped directory:

```text
runs/<run_id>/
```

For **Module 3 Approach 2**, `run_id` is the canonical execution identity.

`sample_id` remains descriptive metadata but does **not** define the root directory.

---

# Local Execution Layout

Example directory structure produced by a run:

```
runs/<run_id>/

├── inputs/
├── work/
├── results/
│   ├── bam/
│   ├── mutect2/
│   └── reports/
├── qc/
├── logs/
└── metadata/
    ├── run_manifest.json
    ├── status.json
    └── artifacts.json
```

---

# Inputs Directory

```
runs/<run_id>/inputs/
```

Contains input material associated with the run.

Examples:

```
SAMPLE_R1.fastq.gz
SAMPLE_R2.fastq.gz
```

Or source tracking material for **SRA-based runs**.

---

# Work Directory

```
runs/<run_id>/work/
```

Contains temporary and intermediate files created during execution.

This directory is **run-scoped and isolated** from other runs.

---

# Metadata Directory

```
runs/<run_id>/metadata/
```

Contains the metadata contract files:

```
run_manifest.json
status.json
artifacts.json
```

These files define:

- run identity  
- lifecycle state  
- produced artifacts  

The metadata directory is the **primary interface between the pipeline and the cloud platform**.

---

# Logs Directory

```
runs/<run_id>/logs/
```

Contains execution logs for debugging and monitoring.

Examples:

```
DEMO1.stdout.log
DEMO1.stderr.log
```

These logs are useful for:

- debugging failed runs  
- exposing error summaries in the dashboard  
- operational troubleshooting  

---

# Results Directory

```
runs/<run_id>/results/
```

Contains structured pipeline outputs.

Example layout:

```
results/

  bam/
    SAMPLE.sorted.markdup.bam

  mutect2/
    SAMPLE.mutect2.filtered.vcf.gz

  reports/
    SAMPLE.report.html
    SAMPLE.PASS.annotated.tsv
    SAMPLE.gene_summary.tsv
```

These are **machine-readable and human-readable outputs** intended for downstream analysis and review.

---

# QC Directory

```
runs/<run_id>/qc/
```

Contains quality-control metrics generated during the pipeline run.

Example:

```
coverage_summary.tsv
per_gene_coverage.tsv
SAMPLE.flagstat.txt
```

These files support **coverage review and run validation**.

---

# Cloud Storage Layout

In cloud deployments, run directories are mirrored to **Cloud Storage**.

Example:

```
gs://somatic-demo-runs/runs/<run_id>/
```

Example object structure:

```
gs://somatic-demo-runs/runs/<run_id>/metadata/run_manifest.json
gs://somatic-demo-runs/runs/<run_id>/metadata/status.json
gs://somatic-demo-runs/runs/<run_id>/metadata/artifacts.json

gs://somatic-demo-runs/runs/<run_id>/logs/DEMO1.stdout.log
gs://somatic-demo-runs/runs/<run_id>/logs/DEMO1.stderr.log

gs://somatic-demo-runs/runs/<run_id>/results/
gs://somatic-demo-runs/runs/<run_id>/qc/
```

---

# Design Principles

The run directory layout follows several principles.

## 1. Run isolation

Every run is fully contained under:

```
runs/<run_id>/
```

This prevents collisions and simplifies cleanup.

---

## 2. Metadata-first structure

The metadata directory allows the API to determine:

- run identity  
- lifecycle state  
- artifact locations  

without scanning the entire directory tree.

---

## 3. Cloud portability

The layout must work identically for:

- local filesystem runs  
- Cloud Run Jobs  
- Cloud Storage buckets  

---

## 4. Stable artifact paths

Artifact paths should remain stable so that the UI and API can link to outputs without special-case logic.

---

# Relationship to Metadata Contract

The metadata files defined in:

```
docs/pipeline/run_manifest.md
```

must always live under:

```
runs/<run_id>/metadata/
```

This ensures that the platform can discover **run state and artifacts consistently**.

---

# Relationship to Later Modules

This layout will be used by:

- **Module 4 — Cloud storage contract**  
- **Module 5 — API artifact lookup**  
- **Module 6 — job execution orchestration**  
- **Module 7 — dashboard artifact links**

Changing this layout later would require **refactoring the API and UI**.
