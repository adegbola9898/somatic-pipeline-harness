# 🧾 Environment Contract

This document defines all environment variables required to run the Somatic Pipeline Platform.

It serves as the **single source of truth** for:

* API configuration
* Cloud Run Job execution
* Deployment and migration
* Infrastructure provisioning (manual or IaC)

---

# 1. 🔧 Core Environment Variables

These variables MUST be defined for the system to function.

## 1.1 Required (API + Job)

```bash
RUNS_BUCKET=
UPLOADS_BUCKET=
GOOGLE_CLOUD_PROJECT=
```

### Description

| Variable             | Description                                                |
| -------------------- | ---------------------------------------------------------- |
| RUNS_BUCKET          | GCS bucket where pipeline outputs and metadata are written |
| UPLOADS_BUCKET       | GCS bucket where input FASTQ files are stored              |
| GOOGLE_CLOUD_PROJECT | GCP project ID used for all services                       |

### Behavior

* API will fail to start if these are missing
* Job will fail at runtime if these are missing

---

## 1.2 Execution Configuration

```bash
REGION=
JOB_NAME=
THREADS=
TARGETS_BED=
```

### Description

| Variable    | Description                                               |
| ----------- | --------------------------------------------------------- |
| REGION      | GCP region where Cloud Run services and jobs are deployed |
| JOB_NAME    | Name of Cloud Run Job used to execute pipeline            |
| THREADS     | Number of threads used by pipeline                        |
| TARGETS_BED | Path to BED file used by pipeline                         |

---

# 2. ⚙️ Job Runtime Variables (Injected by API)

These variables are dynamically set by the API when launching a job.

```bash
RUN_ID=
INPUT_MODE=
SRA=
FASTQ1=
FASTQ2=
FIRESTORE_COLLECTION=runs
```

### Description

| Variable             | Description                             |
| -------------------- | --------------------------------------- |
| RUN_ID               | Unique identifier for the run           |
| INPUT_MODE           | Either `sra` or `fastq_pair`            |
| SRA                  | SRA accession (if using SRA mode)       |
| FASTQ1               | GCS path to R1 FASTQ file               |
| FASTQ2               | GCS path to R2 FASTQ file               |
| FIRESTORE_COLLECTION | Firestore collection used for run state |

---

# 3. 📦 Storage Contract

## Runs Bucket

```text
gs://$RUNS_BUCKET/runs/{run_id}/
```

Must support:

```text
metadata/
logs/
qc/
reports/
outputs/
```

## Uploads Bucket

```text
gs://$UPLOADS_BUCKET/
```

Used for:

* FASTQ inputs
* resolved at runtime to:

```text
/uploads/...
```

---

# 4. 🔁 Execution Assumptions

## API

* Must have access to:

  * Firestore
  * Cloud Run Jobs API
  * GCS (read metadata + artifacts)

## Job

* Must have access to:

  * GCS (read uploads, write runs)
  * Firestore (update run state)
* Must have uploads bucket mounted at:

```text
/uploads
```

---

# 5. 🌐 UI / API Integration

## API URL

The UI must know:

```bash
API_BASE_URL=
```

## CORS

API must allow:

```text
UI_ORIGIN
```

---

# 6. ✅ Deployment Checklist

Before deploying, verify:

```text
[ ] RUNS_BUCKET is set and exists
[ ] UPLOADS_BUCKET is set and exists
[ ] GOOGLE_CLOUD_PROJECT is correct
[ ] REGION is correct
[ ] JOB_NAME exists in Cloud Run Jobs
[ ] THREADS is set
[ ] TARGETS_BED path is valid
[ ] API deployed with env vars
[ ] Job deployed with env vars
[ ] Uploads bucket is mounted to /uploads
[ ] UI configured with correct API base
[ ] API CORS allows UI origin
```

---

# 7. ⚠️ Common Failure Modes

| Issue                 | Cause                        |
| --------------------- | ---------------------------- |
| API fails to start    | Missing required env vars    |
| Job fails immediately | Missing RUN_ID or INPUT_MODE |
| FASTQ runs fail       | Missing `/uploads` mount     |
| Artifacts not found   | Wrong RUNS_BUCKET            |
| UI cannot call API    | CORS or API_BASE mismatch    |
| Job not launching     | Wrong JOB_NAME or REGION     |

---

# 8. 🧠 Design Principle

All system behavior MUST be derived from environment variables.

There must be:

* no hidden defaults
* no hardcoded project-specific values
* no implicit configuration

---

# 9. 🚀 Migration Rule

To migrate to a new project, ONLY these variables should need to change:

```bash
GOOGLE_CLOUD_PROJECT=
RUNS_BUCKET=
UPLOADS_BUCKET=
REGION=
JOB_NAME=
API_BASE_URL=
```

If additional changes are required, the system is not fully portable.
