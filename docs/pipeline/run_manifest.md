# Run Manifest and Metadata Contract

## Purpose

This document defines the metadata contract produced by every pipeline run.

The goal is to make pipeline execution results **machine-readable and consistent** so that the:

- backend API  
- dashboard UI  
- storage layer  
- orchestration logic  

can reliably interpret run outputs.

Each run must produce three metadata files:

```text
run_manifest.json
status.json
artifacts.json
```

These files act as the interface between the **pipeline execution layer** and the **cloud platform layer**.

For **Module 3 Approach 2**, every run is rooted under:

```
runs/<run_id>/
```

- **run_id** is the canonical run identity.  
- **sample_id** is descriptive metadata and does not define the filesystem root.

---

# Metadata Files

## run_manifest.json

Defines the static identity and requested configuration of the run.

This file must be written **before major execution begins**.

### Example

```json
{
  "run_id": "run_20260313_153022_DEMO1",
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
| input_mode | input type, such as `sra` or `fastq_pair` |
| input_uris | submitted input identifiers or file paths |
| submitted_at | run submission timestamp |

---

# status.json

Tracks the lifecycle state of the run.

This file must be created near startup and updated during execution.

### Example during execution

```json
{
  "run_id": "run_20260313_153022_DEMO1",
  "sample_id": "DEMO1",
  "pipeline_version": "0.6",
  "status": "running",
  "current_step": "step_align",
  "submitted_at": "2026-03-13T15:30:22Z",
  "started_at": "2026-03-13T15:30:55Z",
  "finished_at": null,
  "exit_code": null,
  "failure_category": null,
  "failure_message": null,
  "last_updated_at": "2026-03-13T15:42:11Z"
}
```

### Example after completion

```json
{
  "run_id": "run_20260313_153022_DEMO1",
  "sample_id": "DEMO1",
  "pipeline_version": "0.6",
  "status": "succeeded",
  "current_step": null,
  "submitted_at": "2026-03-13T15:30:22Z",
  "started_at": "2026-03-13T15:30:55Z",
  "finished_at": "2026-03-13T16:12:04Z",
  "exit_code": 0,
  "failure_category": null,
  "failure_message": null,
  "last_updated_at": "2026-03-13T16:12:04Z"
}
```

### Run states

| State | Meaning |
|------|--------|
| submitted | run request created |
| queued | accepted but not yet started |
| starting | initialization in progress |
| running | pipeline execution in progress |
| succeeded | pipeline completed successfully |
| failed | pipeline ended with error |
| cancelled | run intentionally stopped |

---

### Failure categories

| Category | Meaning |
|----------|--------|
| user_input | invalid or incompatible user-supplied input |
| pipeline | pipeline/tool execution failure |
| infra | infrastructure or platform failure |
| unknown | failure cause not yet classified |

---

# artifacts.json

Provides a machine-readable inventory of output artifacts produced by the run.

This file should be written near the end of execution and must describe **only files that actually exist**.

### Example

```json
{
  "run_id": "run_20260313_153022_DEMO1",
  "sample_id": "DEMO1",
  "pipeline_version": "0.6",
  "artifact_count": 2,
  "report_html_path": "results/reports/DEMO1.report.html",
  "stdout_log_path": "logs/DEMO1.stdout.log",
  "stderr_log_path": "logs/DEMO1.stderr.log",
  "artifacts": [
    {
      "name": "html_report",
      "type": "report",
      "path": "results/reports/DEMO1.report.html"
    },
    {
      "name": "annotated_variants",
      "type": "table",
      "path": "results/reports/DEMO1.PASS.annotated.tsv"
    }
  ]
}
```

### Required fields

| Field | Description |
|------|-------------|
| run_id | globally unique run identifier |
| sample_id | biological sample identifier |
| pipeline_version | version of the pipeline code |
| artifact_count | number of listed artifacts |
| report_html_path | primary human-readable report path |
| stdout_log_path | stdout log path |
| stderr_log_path | stderr log path |
| artifacts | array of artifact records |

### Artifact fields

| Field | Description |
|------|-------------|
| name | machine-readable artifact identifier |
| type | artifact category |
| path | relative path to file |

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

The pipeline must **not depend on the API**.

The API **reads metadata but does not generate it**.

---

# Required Common Fields

Every metadata file must expose:

- `run_id`  
- `sample_id`  
- `pipeline_version`  

This avoids relying only on filesystem path inference.

---

# Design Principles

Metadata must be **machine-readable**.

Metadata must be **stable across pipeline versions**.

Metadata must **not depend on cloud platform APIs**.

Metadata must **uniquely identify a run and its outputs**.

Intent, execution state, and produced outputs must remain **separated**.

---

# Relationship to Later Modules

This metadata contract enables:

- **Module 4 — storage layout**  
- **Module 5 — API endpoints**  
- **Module 6 — job execution orchestration**  
- **Module 7 — dashboard run views**

Without this contract, the platform cannot reliably interpret pipeline results.
