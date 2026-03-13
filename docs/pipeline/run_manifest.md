# Run Manifest and Metadata Contract

## Purpose

This document defines the metadata contract produced by every pipeline run.

The goal is to make pipeline execution results **machine-readable and consistent** so that the:

- backend API  
- dashboard UI  
- storage layer  
- orchestration logic  

can reliably interpret run outputs.

Each run must produce three metadata files.

```
run_manifest.json
status.json
artifacts.json
```

These files act as the interface between the **pipeline execution layer** and the **cloud platform layer**.

---

# Metadata Files

## run_manifest.json

Defines the static identity and configuration of the run.

This file should be written **at the start of the run**.

Example:

```json
{
  "run_id": "run_20260313_153022_ab12",
  "sample_id": "DEMO1",
  "pipeline_version": "0.6",
  "container_image": "us-central1-docker.pkg.dev/proven-impact-229112/somatic-pipeline/somatic-harness:0.6",
  "reference_version": "refs-grch38-bwamem2-r115-v1",
  "targets_bed_version": "targets-34genes-ensembl115-v1.gene_labeled_pad10.bed",
  "input_mode": "sra",
  "input_uris": ["ERR7252107"],
  "submitted_at": "2026-03-13T15:30:22Z"
}
```

### Required fields

| Field | Description |
|------|-------------|
| run_id | globally unique run identifier |
| sample_id | biological sample identifier |
| pipeline_version | version of the pipeline code |
| container_image | container image used for execution |
| reference_version | reference bundle identifier |
| targets_bed_version | target panel identifier |
| submitted_at | run submission timestamp |

---

# status.json

Tracks the lifecycle state of the run.

This file should be updated during execution.

### Example during execution

```json
{
  "run_id": "run_20260313_153022_ab12",
  "status": "running",
  "submitted_at": "2026-03-13T15:30:22Z",
  "started_at": "2026-03-13T15:30:55Z",
  "finished_at": null,
  "exit_code": null,
  "error_summary": null
}
```

### Example after completion

```json
{
  "run_id": "run_20260313_153022_ab12",
  "status": "succeeded",
  "submitted_at": "2026-03-13T15:30:22Z",
  "started_at": "2026-03-13T15:30:55Z",
  "finished_at": "2026-03-13T16:12:04Z",
  "exit_code": 0,
  "error_summary": null
}
```

### Run States

| State | Meaning |
|------|--------|
| submitted | run accepted by API |
| running | pipeline execution in progress |
| succeeded | pipeline completed successfully |
| failed | pipeline ended with error |

---

# artifacts.json

Provides a machine-readable inventory of output artifacts produced by the run.

Example:

```json
{
  "run_id": "run_20260313_153022_ab12",
  "artifacts": [
    {
      "artifact_type": "html_report",
      "display_name": "HTML report",
      "path": "results/reports/DEMO1.report.html",
      "content_type": "text/html"
    },
    {
      "artifact_type": "annotated_variants",
      "display_name": "Annotated PASS variants",
      "path": "results/reports/DEMO1.PASS.annotated.tsv",
      "content_type": "text/tab-separated-values"
    }
  ]
}
```

### Artifact fields

| Field | Description |
|------|-------------|
| artifact_type | machine-readable artifact identifier |
| display_name | human-friendly label |
| path | relative path to file |
| content_type | MIME type |

---

# Storage Location

Metadata files must live under a run-scoped metadata directory.

### Example local structure

```
runs/<run_id>/metadata/
    run_manifest.json
    status.json
    artifacts.json
```

### Example cloud storage structure

```
gs://somatic-demo-runs/runs/<run_id>/metadata/
    run_manifest.json
    status.json
    artifacts.json
```

---

# Ownership Rules

| Component | Responsibility |
|-----------|---------------|
| pipeline | writes metadata files |
| API | reads metadata files |
| dashboard | displays metadata |
| storage | stores metadata |

The pipeline must not depend on the API.

The API reads metadata but does not generate it.

---

# Required Metadata Fields

Every run must expose:

- `run_id`  
- `sample_id`  
- `pipeline_version`  
- `container_image`  
- `reference_version`  
- `targets_bed_version`  
- `submitted_at`  
- `started_at`  
- `finished_at`  
- `status`  
- `exit_code`  
- artifact paths  

---

# Design Principles

Metadata must be machine readable.

Metadata must be stable across pipeline versions.

Metadata must not depend on cloud platform APIs.

Metadata must uniquely identify a run and its outputs.

---

# Relationship to Later Modules

This metadata contract enables:

- **Module 4 — storage layout**  
- **Module 5 — API endpoints**  
- **Module 6 — job execution orchestration**  
- **Module 7 — dashboard run views**

Without this contract, the platform cannot reliably interpret pipeline results.
