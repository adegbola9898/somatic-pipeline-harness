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

# Run Directory Structure

Each pipeline execution is represented by a unique **run_id**.

All outputs for that run are stored under a run-scoped directory.

Example:

```
runs/<run_id>/
```

---

# Local Execution Layout

Example directory structure produced by a run:

```
runs/<run_id>/

├── metadata/
│   ├── run_manifest.json
│   ├── status.json
│   └── artifacts.json
│
├── logs/
│   ├── pipeline.log
│   └── step_logs/
│
├── results/
│   ├── bam/
│   ├── mutect2/
│   └── reports/
│
├── reports/
│   └── SAMPLE.report.html
│
└── qc/
    ├── coverage_summary.tsv
    └── per_gene_coverage.tsv
```

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
pipeline.log
step_align.log
step_mutect.log
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
    SAMPLE.PASS.annotated.tsv
    SAMPLE.gene_summary.tsv
```

These are machine-readable outputs intended for downstream analysis.

---

# Reports Directory

```
runs/<run_id>/reports/
```

Contains human-readable summary outputs.

Example:

```
SAMPLE.report.html
```

This report is the primary artifact linked in the dashboard UI.

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

These files support coverage review and run validation.

---

# Cloud Storage Layout

In cloud deployments, run directories are mirrored to Cloud Storage.

Example:

```
gs://somatic-demo-runs/runs/<run_id>/
```

Example object structure:

```
gs://somatic-demo-runs/runs/<run_id>/metadata/run_manifest.json
gs://somatic-demo-runs/runs/<run_id>/metadata/status.json
gs://somatic-demo-runs/runs/<run_id>/metadata/artifacts.json

gs://somatic-demo-runs/runs/<run_id>/logs/pipeline.log

gs://somatic-demo-runs/runs/<run_id>/results/

gs://somatic-demo-runs/runs/<run_id>/reports/SAMPLE.report.html
```

---

# Design Principles

The run directory layout follows several principles.

### 1. Run isolation

Every run is fully contained under:

```
runs/<run_id>/
```

This prevents collisions and simplifies cleanup.

---

### 2. Metadata-first structure

The metadata directory allows the API to determine:

- run identity  
- lifecycle state  
- artifact locations  

without scanning the entire directory tree.

---

### 3. Cloud portability

The layout must work identically for:

- local filesystem runs  
- Cloud Run Jobs  
- Cloud Storage buckets  

---

### 4. Stable artifact paths

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

This ensures that the platform can discover run state and artifacts consistently.

---

# Relationship to Later Modules

This layout will be used by:

- **Module 4 — Cloud storage contract**  
- **Module 5 — API artifact lookup**  
- **Module 6 — job execution orchestration**  
- **Module 7 — dashboard artifact links**

Changing this layout later would require refactoring the API and UI.
