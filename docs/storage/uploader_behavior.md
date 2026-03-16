# Module 4 — Cloud Run Uploader Behavior Specification

## Purpose

This document defines the expected behavior of the **run uploader component** responsible for publishing a completed or in-progress pipeline run to cloud storage.

The uploader implements the storage contract defined in:

```
docs/storage/upload_contract.md
```

This document specifies **behavior**, not implementation.

---

# Uploader Role

The uploader is responsible for publishing the **consumer-visible run record** to cloud storage.

The uploader:

- reads artifacts from the local run root
- uploads artifacts according to the storage contract
- ensures metadata files reflect the final durable state
- guarantees artifact layout invariants

The uploader does **not** run the pipeline.

---

# Inputs

The uploader receives:

```
run_id
sample_id
run_root
bucket
```

Example:

```
run_id=run_metadata_smoke_001
sample_id=DEMO1
run_root=runs/run_metadata_smoke_001
bucket=my-somatic-platform
```

Target cloud prefix:

```
gs://<bucket>/runs/<run_id>/
```

---

# Responsibilities

The uploader must:

1. upload required artifacts
2. respect path mapping rules
3. preserve filenames
4. upload metadata files
5. avoid uploading excluded directories
6. support idempotent re-execution

The uploader must **not**:

- rename artifacts
- infer artifacts by scanning the bucket
- upload execution-local directories

---

# Upload Mapping

Uploader applies the mapping defined in:

```
docs/storage/upload_contract.md
```

Summary:

| Local | Cloud |
|------|------|
| metadata | metadata |
| logs | logs |
| qc | qc |
| results/reports | reports |
| results/bam | outputs/bam |
| results/mutect2 | outputs/mutect2 |

---

# Upload Ordering

Uploads should occur in the following logical order:

1. logs  
2. qc  
3. outputs  
4. reports  
5. metadata  

Metadata is uploaded **last** to ensure it reflects the durable artifact state.

---

# Metadata Finalization

Metadata finalization must follow **ADR-0002 ordering**.

The uploader must ensure:

```
metadata/run_manifest.json
metadata/status.json
metadata/artifacts.json
```

represent the **final durable record** at upload completion.

Only after metadata is successfully written should the system mark the run finalized in Firestore.

---

# Idempotency

Uploader execution must be **safe to run multiple times**.

Running the uploader again should:

- produce identical object paths
- not create duplicate artifacts
- not modify filenames

This allows safe retry if a job crashes mid-upload.

---

# Failure Handling

If upload fails mid-run:

- already-uploaded artifacts remain valid
- uploader may be safely re-run

Metadata files should only represent artifacts that were successfully produced.

Uploader must **not fabricate artifact records**.

---

# Excluded Paths

Uploader must never upload:

```
runs/<run_id>/inputs/
runs/<run_id>/work/
```

These directories are execution-local.

---

# Contract Enforcement

Uploader must comply with:

```
docs/storage/upload_contract.md
```

That document defines:

- required artifacts
- optional artifacts
- naming invariants
- storage layout

This document defines **behavior for publishing those artifacts**.

---

# Non-Goals

The uploader specification does not define:

- retry backoff policy
- resumable upload protocol
- multipart upload implementation
- object lifecycle management
- cloud IAM policy
- cross-region replication

These concerns may be addressed later.

---

# Go / No-Go Criteria

Uploader behavior specification is complete when:

- uploader responsibilities are defined
- uploader inputs are defined
- upload ordering is defined
- idempotency rules are defined
- failure handling rules are defined
- metadata finalization ordering is defined
