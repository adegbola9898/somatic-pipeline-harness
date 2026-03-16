# Module 4 — Cloud Storage Upload Contract

## Purpose

This document defines the **v1 cloud storage contract** for a completed or in-progress somatic pipeline run.

It standardizes what the uploader places into cloud object storage under:

```text
gs://<bucket>/runs/<run_id>/
```

This contract is part of the platform's durable metadata plane and is consumed by the API and UI for finalized run details and artifact retrieval.

This document does not redefine the local execution layout. Local execution remains run-rooted and execution-oriented under:

```text
runs/<run_id>/
```

The cloud layout is intentionally consumer-oriented.

---

## ADR Alignment

This document follows **ADR-0002: Hybrid Control Plane + Durable Metadata Plane**.

Under that ADR:

- **Firestore** is authoritative for:
  - live operational state
  - dashboard polling
  - run listing
  - filtering
  - orchestration status

- **Cloud Storage metadata** is authoritative for:
  - the durable execution record
  - final lifecycle record
  - artifact inventory

Artifact discovery must use storage metadata files, especially:

```text
metadata/artifacts.json
```

and **must not rely on bucket prefix scanning**.

This document defines the **Cloud Storage side** of that contract only.

---

## Scope

This contract defines:

- required uploaded artifacts
- optional uploaded artifacts
- excluded artifacts
- path mapping rules
- upload behavior
- naming invariants
- success vs failure upload policy

This contract applies to **v1 of the cloud execution platform**.

---

# Cloud Run Root

Each run uploads into a dedicated cloud prefix:

```text
gs://<bucket>/runs/<run_id>/
```

Within that prefix, objects must be organized as:

```text
gs://<bucket>/runs/<run_id>/
├── metadata/
├── logs/
├── reports/
├── outputs/
└── qc/
```

These directories are **logical object prefixes**, not required physical folders.

---

# Design Rules

## 1. Metadata-first artifact discovery

Artifact discovery by the API and UI must use:

```text
metadata/status.json
metadata/artifacts.json
```

The API **must not scan the bucket** to infer artifact existence.

---

## 2. Firestore and Storage have different authority boundaries

This storage contract does **not replace the Firestore control plane**.

- **Firestore** is authoritative for live operational state.
- **Storage metadata** is authoritative for:
  - durable execution record
  - finalized lifecycle record
  - artifact inventory.

---

## 3. Cloud layout is consumer-oriented

Cloud storage is organized for **downstream consumption by API/UI**, not for execution.

---

## 4. QC is first-class

QC artifacts must remain directly addressable under:

```text
qc/
```

because the dashboard will display them directly.

---

## 5. Inputs and work directories are execution-local

Execution-local directories are **excluded** from the v1 cloud contract.

---

# Local to Cloud Mapping

The uploader must map local run outputs to cloud paths as follows.

| Local path | Cloud path |
|---|---|
| runs/<run_id>/metadata/ | metadata/ |
| runs/<run_id>/logs/ | logs/ |
| runs/<run_id>/qc/ | qc/ |
| runs/<run_id>/results/reports/ | reports/ |
| runs/<run_id>/results/bam/ | outputs/bam/ |
| runs/<run_id>/results/mutect2/ | outputs/mutect2/ |

---

# Required Uploads (v1)

The following artifacts are **required for v1** when they exist for a run category.

---

# 1. Metadata

Required cloud prefix:

```text
metadata/
```

Required objects:

```text
metadata/run_manifest.json
metadata/status.json
metadata/artifacts.json
```

### Requirements

These files are **always uploaded for every run**.

They are the authoritative **storage-side machine-readable record** for:

- finalized execution provenance
- artifact inventory

Additional rules:

- `status.json` must reflect the **latest known pipeline lifecycle state** available at upload completion.
- `artifacts.json` must enumerate **produced artifacts**, even if some optional artifacts are absent.

---

# 2. Logs

Required cloud prefix:

```text
logs/
```

Required objects:

```text
logs/<sample_id>.stdout.log
logs/<sample_id>.stderr.log
```

### Requirements

Standard output and standard error logs must be uploaded for **every run**.

These logs remain required for:

- successful runs
- failed runs

Log filenames are **sample-rooted**, not run-rooted.

---

# 3. Reports

Required cloud prefix:

```text
reports/
```

Required objects for a **successful run**:

```text
reports/<sample_id>.report.html
reports/<sample_id>.PASS.annotated.tsv
reports/<sample_id>.gene_summary.tsv
reports/<sample_id>.PASS.flagged.tsv
reports/<sample_id>.PASS.somaticish.tsv
reports/<sample_id>.PASS.germlineish.tsv
reports/<sample_id>.PASS.uncertain.tsv
```

### Requirements

These files are required for **successful runs that reach report generation**.

- The HTML report is the **primary human-readable review artifact**.
- Review tables remain directly addressable under `reports/`.

---

# 4. QC

Required cloud prefix:

```text
qc/
```

Required objects for a successful run:

```text
qc/coverage_summary.tsv
qc/per_gene_coverage.tsv
qc/qc_gate.tsv
qc/<sample_id>.flagstat.txt
```

### Requirements

QC outputs are **first-class dashboard inputs**.

QC files must **not be nested under `reports/` or `outputs/`**.

QC paths should remain **stable and directly fetchable by API/UI**.

---

# 5. Core Outputs

Required cloud prefix:

```text
outputs/
```

Required objects for a successful run:

```text
outputs/bam/<sample_id>.sorted.markdup.bam
outputs/bam/<sample_id>.sorted.markdup.bam.bai
outputs/mutect2/*.vcf.gz
```

### Requirements

- BAM and BAM index are **required final alignment outputs**.
- Core **Mutect2 compressed VCF outputs** are required final variant outputs.

The uploader may upload multiple `.vcf.gz` files under:

```text
outputs/mutect2/
```

The exact set of VCF files present must be described in:

```text
metadata/artifacts.json
```

---

# Optional Uploads

Optional uploads may be present when generated by the pipeline but are **not required for v1 contract compliance**.

Examples:

```text
outputs/mutect2/*.f1r2.tar.gz
outputs/mutect2/read-orientation-model.tar.gz
metadata/legacy_*.json
metadata/*.legacy.json
```

### Rules for optional uploads

- Optional uploads must **not replace required uploads**.
- Optional uploads must **not be required by API/UI for basic run rendering**.
- Optional uploads **may be referenced** in `metadata/artifacts.json`.
- Optional uploads must remain under the same **top-level consumer-oriented prefixes**:
  - `metadata/`
  - `logs/`
  - `reports/`
  - `outputs/`
  - `qc/`

---

# Excluded from Upload (v1)

The following local paths are **explicitly excluded** from the v1 cloud contract:

```text
runs/<run_id>/inputs/
runs/<run_id>/work/
```

Also excluded:

- transient temp files
- scratch files
- intermediate execution-only artifacts not needed by API/UI
- uploader implementation state files
- partial/incomplete files that were not finalized by the pipeline

### Rationale

`inputs/` and `work/` are **execution-local**, not consumer-facing.

v1 cloud storage is intended for:

- run inspection
- downstream integration

—not full execution replay from bucket contents alone.

---

# Naming Invariants

The uploader must preserve the following naming rules.

---

## 1. Run-rooted cloud prefix

Every uploaded object must live under:

```text
runs/<run_id>/
```

No artifacts for a run may be uploaded outside that run root.

---

## 2. Stable top-level prefixes

Only these top-level prefixes are used in v1:

```text
metadata/
logs/
reports/
outputs/
qc/
```

---

## 3. Metadata filenames are fixed

Metadata object names are fixed:

```text
metadata/run_manifest.json
metadata/status.json
metadata/artifacts.json
```

These filenames **must not be sample-specific**.

---

## 4. User-facing result files remain sample-rooted

Where applicable, filenames must preserve the pipeline’s existing naming.

Examples:

```text
logs/<sample_id>.stdout.log
logs/<sample_id>.stderr.log

reports/<sample_id>.report.html
reports/<sample_id>.gene_summary.tsv

qc/<sample_id>.flagstat.txt

outputs/bam/<sample_id>.sorted.markdup.bam
outputs/bam/<sample_id>.sorted.markdup.bam.bai
```

---

## 5. No renaming during upload beyond path remapping

The uploader may **remap directory placement** from local to cloud, but must **not invent new filenames**.

Example:

Allowed:

```text
results/bam/<sample_id>.sorted.markdup.bam
→ outputs/bam/<sample_id>.sorted.markdup.bam
```

Not allowed:

```text
results/bam/<sample_id>.sorted.markdup.bam
→ outputs/bam/final.bam
```

---

## 6. Artifact paths in storage metadata are authoritative

API/UI artifact retrieval should rely on:

```text
metadata/artifacts.json
```

—not on cloud prefix listing heuristics.

---

# Upload Behavior

## 1. Upload unit

Uploads are defined **at the run level**.

A single run uploader publishes the cloud-visible storage contract for **one `run_id`**.

---

## 2. Path-preserving category remap

Upload behavior:

- preserve the artifact filename
- remap from **local execution directory** to **cloud consumer-oriented prefix**

---

## 3. Storage metadata must represent latest durable state

At minimum the cloud copy of:

```text
metadata/status.json
metadata/artifacts.json
```

must represent the **latest known durable state** when upload completes.

---

## 4. Artifacts.json is the storage artifact inventory

Artifact discovery works as follows:

```
uploader publishes files
uploader publishes metadata/artifacts.json
API/UI consume metadata contract
```

The uploader must **not expect the API to rediscover artifacts** by listing cloud prefixes.

---

## 5. Idempotent uploads are preferred

Re-uploading the same completed run should produce the **same cloud object layout and filenames**.

The contract assumes **deterministic artifact naming**.

---

## 6. Finalization ordering (ADR-0002)

A run is **not storage-finalized** until storage metadata has been successfully written.

Operational ordering:

```
1. write final storage metadata
2. upload required outputs and reports if not already present
3. update Firestore to final state with metadata_finalized = true
```

This preserves the **authority boundary defined in ADR-0002**.

---

# Success vs Failure Upload Policy

## Successful runs

A successful run is expected to upload:

- required metadata
- required logs
- required reports
- required QC artifacts
- required core outputs
- any optional artifacts generated

Successful runs should produce the **full v1 consumer-facing durable run record**.

---

## Failed runs

A failed run must still upload:

```text
metadata/run_manifest.json
metadata/status.json
metadata/artifacts.json
logs/<sample_id>.stdout.log
logs/<sample_id>.stderr.log
```

### Failure rules

- `status.json` must indicate failure state and include failure details.
- `artifacts.json` may contain only artifacts produced before failure.
- Missing reports/QC/core outputs are acceptable.

The uploader must **never synthesize placeholder scientific outputs**.

---

## Cancelled runs

Cancelled runs follow the same expectations as failed runs:

- metadata must be uploaded
- logs must be uploaded if present
- only real produced artifacts may appear in `artifacts.json`

---

# Contract Compliance Summary

A run is **minimally upload-contract compliant** when it includes:

```text
metadata/run_manifest.json
metadata/status.json
metadata/artifacts.json
logs/<sample_id>.stdout.log
logs/<sample_id>.stderr.log
```

A run is **fully successful-upload compliant** when it also includes required artifacts under:

```text
reports/
qc/
outputs/
```

subject to the pipeline actually producing them.

---

# Worked Example

Given:

```text
bucket: my-somatic-platform
run_id: run_metadata_smoke_001
sample_id: DEMO1
```

### Local layout

```text
runs/run_metadata_smoke_001/
├── logs/
│   ├── DEMO1.stdout.log
│   └── DEMO1.stderr.log
├── metadata/
│   ├── run_manifest.json
│   ├── status.json
│   └── artifacts.json
├── qc/
│   ├── coverage_summary.tsv
│   ├── per_gene_coverage.tsv
│   ├── qc_gate.tsv
│   └── DEMO1.flagstat.txt
└── results/
    ├── bam/
    │   ├── DEMO1.sorted.markdup.bam
    │   └── DEMO1.sorted.markdup.bam.bai
    ├── mutect2/
    │   ├── DEMO1.unfiltered.vcf.gz
    │   ├── DEMO1.filtered.vcf.gz
    │   └── read-orientation-model.tar.gz
    └── reports/
        ├── DEMO1.report.html
        ├── DEMO1.PASS.annotated.tsv
        ├── DEMO1.gene_summary.tsv
        ├── DEMO1.PASS.flagged.tsv
        ├── DEMO1.PASS.somaticish.tsv
        ├── DEMO1.PASS.germlineish.tsv
        └── DEMO1.PASS.uncertain.tsv
```

### Cloud layout

```text
gs://my-somatic-platform/runs/run_metadata_smoke_001/
├── metadata/
│   ├── run_manifest.json
│   ├── status.json
│   └── artifacts.json
├── logs/
│   ├── DEMO1.stdout.log
│   └── DEMO1.stderr.log
├── reports/
│   ├── DEMO1.report.html
│   ├── DEMO1.PASS.annotated.tsv
│   ├── DEMO1.gene_summary.tsv
│   ├── DEMO1.PASS.flagged.tsv
│   ├── DEMO1.PASS.somaticish.tsv
│   ├── DEMO1.PASS.germlineish.tsv
│   └── DEMO1.PASS.uncertain.tsv
├── qc/
│   ├── coverage_summary.tsv
│   ├── per_gene_coverage.tsv
│   ├── qc_gate.tsv
│   └── DEMO1.flagstat.txt
└── outputs/
    ├── bam/
    │   ├── DEMO1.sorted.markdup.bam
    │   └── DEMO1.sorted.markdup.bam.bai
    └── mutect2/
        ├── DEMO1.unfiltered.vcf.gz
        ├── DEMO1.filtered.vcf.gz
        └── read-orientation-model.tar.gz
```

Notes:

- `read-orientation-model.tar.gz` is **optional**.
- Firestore still provides the **live run summary view**.
- Storage metadata remains the **durable artifact and provenance contract**.
- API/UI should use **storage metadata**, not bucket scanning.

---

# Non-Goals for v1

This contract does **not define**:

- object lifecycle retention policy
- bucket IAM policy
- signed URL generation
- resumable upload implementation details
- multipart upload strategy
- checksum enforcement policy
- cross-region replication
- archival storage tiering
- Firestore schema design

These concerns may be addressed in later modules **without changing the path contract defined here**.

## Go/No-Go Criteria for Module 4

Module 4 storage contract documentation is complete when:

- the cloud run-root path is defined
- required uploaded artifacts are enumerated
- optional uploaded artifacts are enumerated
- excluded artifacts are explicit
- local-to-cloud mapping is explicit
- upload behavior is defined
- naming invariants are explicit
- success vs failure upload policy is explicit
- ADR-0002 authority boundaries are preserved
- a worked example is included

Module 4 is not complete if any of the above remain ambiguous or if the document requires bucket scanning for artifact discovery.
