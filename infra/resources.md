# ☁️ Resource Map

This document defines all cloud resources required by the Somatic Pipeline Platform.

It provides a **single, authoritative view of infrastructure components**, their roles, and how they relate to each other.

---

# 1. 🧱 Overview

The platform is composed of:

* Cloud Run services (UI + API)
* Cloud Run Job (pipeline execution)
* Firestore (state store)
* Google Cloud Storage (data plane)

---

# 2. 🌐 Cloud Run Services

## 2.1 API Service

```text id="api_svc"
Service Name: somatic-pipeline-api
Type: Cloud Run (Service)
```

### Responsibilities

* Accept run submissions (`POST /runs`)
* Orchestrate execution via Cloud Run Jobs
* Read/write run state from Firestore
* Serve artifacts from GCS
* Expose public API endpoints

### Dependencies

* Firestore (`runs` collection)
* Cloud Run Job (execution trigger)
* GCS (metadata + artifacts)

---

## 2.2 UI Service

```text id="ui_svc"
Service Name: somatic-pipeline-ui
Type: Cloud Run (Service)
```

### Responsibilities

* Provide user interface
* Submit runs via API
* Display run status and results
* Fetch logs and artifacts via API

### Dependencies

* API service (HTTP)
* Browser environment

---

# 3. ⚙️ Cloud Run Job

## 3.1 Pipeline Runner

```text id="job_svc"
Job Name: somatic-pipeline-runner
Type: Cloud Run Job
```

### Responsibilities

* Execute somatic pipeline
* Resolve inputs (SRA / FASTQ)
* Run analysis
* Upload results to GCS
* Update Firestore state

### Runtime Requirements

* Environment variables injected by API
* Access to:

  * Firestore
  * runs bucket (write)
  * uploads bucket (read)

### Special Requirement

```text id="uploads_mount"
/uploads must be mounted to UPLOADS_BUCKET
```

---

# 4. 🧠 Firestore

## 4.1 Database

```text id="fs_db"
Type: Firestore (Native mode)
```

---

## 4.2 Collection

```text id="fs_collection"
Collection: runs
```

### Responsibilities

* Store run lifecycle state
* Track execution metadata
* Store failure information
* Provide query interface for API

---

## 4.3 Example Document

```json id="fs_example"
{
  "run_id": "...",
  "status": "submitted | running | succeeded | failed",
  "metadata_finalized": true,
  "created_at": "...",
  "updated_at": "...",
  "input_mode": "...",
  "runs_bucket": "...",
  "uploads_bucket": "...",
  "failure_category": "...",
  "failure_reason": "..."
}
```

---

# 5. 📦 Google Cloud Storage

## 5.1 Runs Bucket

```text id="runs_bucket"
Bucket: gs://$RUNS_BUCKET
```

### Responsibilities

* Store pipeline outputs
* Store metadata files
* Store logs and reports

### Structure

```text id="runs_layout"
runs/{run_id}/
  metadata/
  logs/
  qc/
  reports/
  outputs/
```

---

## 5.2 Uploads Bucket

```text id="uploads_bucket"
Bucket: gs://$UPLOADS_BUCKET
```

### Responsibilities

* Store input FASTQ files

### Runtime Behavior

```text id="uploads_behavior"
gs://... → /uploads/...
```

Resolved inside Cloud Run Job.

---

# 6. 🔐 Service Accounts & Access (Conceptual)

## API Service

Must be able to:

* Read/write Firestore
* Launch Cloud Run Jobs
* Read GCS artifacts

---

## Job Service

Must be able to:

* Read uploads bucket
* Write runs bucket
* Update Firestore
* Access logging

---

# 7. 🔗 Resource Relationships

```text id="resource_flow"
UI → API → Firestore
           ↓
           Cloud Run Job
           ↓
           Pipeline Execution
           ↓
           GCS (runs bucket)
           ↓
API → reads metadata/artifacts → UI
```

---

# 8. 📍 Deployment Mapping

| Component      | Resource Type     | Scope        |
| -------------- | ----------------- | ------------ |
| API            | Cloud Run Service | regional     |
| UI             | Cloud Run Service | regional     |
| Job            | Cloud Run Job     | regional     |
| Firestore      | Database          | project-wide |
| Runs Bucket    | GCS               | project-wide |
| Uploads Bucket | GCS               | project-wide |

---

# 9. ⚠️ Critical Constraints

## 9.1 API Dependency

* API MUST be deployed after:

  * Firestore
  * Job
  * Buckets

---

## 9.2 Job Dependency

* Job MUST be deployed after:

  * Buckets
  * Service account permissions

---

## 9.3 UI Dependency

* UI MUST be deployed after:

  * API URL is known
  * CORS is configured

---

# 10. 🚀 Migration Rule

To recreate the platform in a new project, the following resources MUST exist:

```text id="migration_resources"
[ ] Cloud Run API service
[ ] Cloud Run UI service
[ ] Cloud Run Job
[ ] Firestore database (runs collection)
[ ] Runs bucket
[ ] Uploads bucket
```

If any are missing, the system is incomplete.

---

# 11. 🧠 Design Principle

Each resource has a **single responsibility**:

* API = control plane
* Job = execution plane
* GCS = data plane
* Firestore = state plane

This separation MUST be preserved.
