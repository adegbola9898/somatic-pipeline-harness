# 🚀 Migration / Deployment Playbook

This document describes how to deploy or migrate the Somatic Pipeline Platform into a new Google Cloud project.

It is intended to be used as a **repeatable checklist** when:

* moving to a new GCP project
* recreating the platform from scratch
* validating portability of the system

---

# 1. 🎯 Goal

Provision and deploy a working environment containing:

* Cloud Run API service
* Cloud Run UI service
* Cloud Run Job runner
* Firestore database
* GCS runs bucket
* GCS uploads bucket

---

# 2. 📋 Prerequisites

Before starting, confirm:

* Google Cloud CLI is installed
* Docker or Cloud Build is available
* repository is cloned locally
* correct branch is checked out
* you have permission to create resources in the target project

Recommended repo branch for full platform deployment:

```bash
git checkout phase1-config-hardening
```

---

# 3. 🆕 Step 1 — Create Project

Create a new Google Cloud project.

Record:

```bash
PROJECT_ID=
REGION=
```

Example:

```bash
PROJECT_ID=my-new-somatic-project
REGION=us-central1
```

Set active project:

```bash
gcloud config set project "$PROJECT_ID"
```

---

# 4. ⚙️ Step 2 — Enable Required APIs

Enable all required platform services:

```bash
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com \
  storage.googleapis.com \
  logging.googleapis.com
```

---

# 5. 🧠 Step 3 — Create Firestore

Create Firestore database in **Native mode**.

Required collection:

```text
runs
```

This collection will store run state and execution metadata.

---

# 6. 📦 Step 4 — Create Buckets

Define bucket names:

```bash
RUNS_BUCKET=
UPLOADS_BUCKET=
```

Create buckets:

```bash
gcloud storage buckets create "gs://$RUNS_BUCKET" --location="$REGION"
gcloud storage buckets create "gs://$UPLOADS_BUCKET" --location="$REGION"
```

Validate:

```bash
gcloud storage buckets describe "gs://$RUNS_BUCKET"
gcloud storage buckets describe "gs://$UPLOADS_BUCKET"
```

---

# 7. 🏗️ Step 5 — Build and Push Images

Define image targets:

```bash
REPO_HOST="${REGION}-docker.pkg.dev"
AR_REPO="somatic-pipeline"

API_IMAGE="${REPO_HOST}/${PROJECT_ID}/${AR_REPO}/somatic-api:latest"
UI_IMAGE="${REPO_HOST}/${PROJECT_ID}/${AR_REPO}/somatic-ui:latest"
JOB_IMAGE="${REPO_HOST}/${PROJECT_ID}/${AR_REPO}/somatic-job:latest"
```

Create Artifact Registry repository if needed:

```bash
gcloud artifacts repositories create somatic-pipeline \
  --repository-format=docker \
  --location="$REGION" \
  --description="Somatic pipeline images"
```

Configure Docker auth:

```bash
gcloud auth configure-docker "${REGION}-docker.pkg.dev"
```

Build API image:

```bash
gcloud builds submit api --tag "$API_IMAGE"
```

Build UI image:

```bash
gcloud builds submit ui --tag "$UI_IMAGE"
```

Build Job image:

```bash
gcloud builds submit . --tag "$JOB_IMAGE"
```

---

# 8. 🔧 Step 6 — Set Environment Variables

Define deployment variables:

```bash
GOOGLE_CLOUD_PROJECT="$PROJECT_ID"
RUNS_BUCKET=
UPLOADS_BUCKET=
REGION=
JOB_NAME=somatic-pipeline-runner
THREADS=8
TARGETS_BED=/refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed
FIRESTORE_COLLECTION=runs
```

These values must be set consistently across API and Job deployments.

---

# 9. 🌐 Step 7 — Deploy API

Deploy API Cloud Run service:

```bash
gcloud run deploy somatic-pipeline-api \
  --image "$API_IMAGE" \
  --region "$REGION" \
  --allow-unauthenticated \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=$PROJECT_ID,RUNS_BUCKET=$RUNS_BUCKET,UPLOADS_BUCKET=$UPLOADS_BUCKET,REGION=$REGION,JOB_NAME=$JOB_NAME,THREADS=$THREADS,TARGETS_BED=$TARGETS_BED"
```

Get deployed API URL:

```bash
API_URL="$(gcloud run services describe somatic-pipeline-api --region "$REGION" --format='value(status.url)')"
echo "$API_URL"
```

Validate health:

```bash
curl "$API_URL/health"
```

Expected:

```json
{"status":"ok"}
```

---

# 10. 🖥️ Step 8 — Deploy UI

Before deploying UI, ensure it is configured with the correct API base URL.

Then deploy:

```bash
gcloud run deploy somatic-pipeline-ui \
  --image "$UI_IMAGE" \
  --region "$REGION" \
  --allow-unauthenticated
```

Get deployed UI URL:

```bash
UI_URL="$(gcloud run services describe somatic-pipeline-ui --region "$REGION" --format='value(status.url)')"
echo "$UI_URL"
```

---

# 11. ⚙️ Step 9 — Deploy Job

Deploy Cloud Run Job:

```bash
gcloud run jobs deploy "$JOB_NAME" \
  --image "$JOB_IMAGE" \
  --region "$REGION" \
  --tasks 1 \
  --max-retries 0 \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=$PROJECT_ID,RUNS_BUCKET=$RUNS_BUCKET,UPLOADS_BUCKET=$UPLOADS_BUCKET,FIRESTORE_COLLECTION=$FIRESTORE_COLLECTION,THREADS=$THREADS,TARGETS_BED=$TARGETS_BED"
```

Important runtime requirement:

```text
/uploads must be mounted to the uploads bucket
```

This is required for FASTQ mode.

---

# 12. 🔐 Step 10 — Configure CORS and UI/API Wiring

Update API CORS allowlist so the deployed UI origin is allowed.

Also ensure the UI points to the deployed API URL.

Required values:

```bash
API_URL=
UI_URL=
```

Validation check:

* UI loads successfully
* browser can call API
* no CORS errors

---

# 13. 🧪 Step 11 — Validate End-to-End

## API checks

```bash
curl "$API_URL/health"
curl "$API_URL/runs"
```

## FASTQ test submission

```bash
curl -X POST "$API_URL/runs" \
  -H "Content-Type: application/json" \
  -d "{
    \"request\": {
      \"fastq1\": \"gs://$UPLOADS_BUCKET/FASTP_PROOF_R1.fastq.gz\",
      \"fastq2\": \"gs://$UPLOADS_BUCKET/FASTP_PROOF_R2.fastq.gz\"
    }
  }"
```

## Verify outputs

Check:

* Firestore has run document
* Job launched successfully
* outputs uploaded to runs bucket
* report/log endpoints work

---

# 14. ✅ Final Deployment Checklist

```text
[ ] Project created
[ ] Required APIs enabled
[ ] Firestore created in Native mode
[ ] Runs bucket created
[ ] Uploads bucket created
[ ] Artifact Registry repository created
[ ] API image built and pushed
[ ] UI image built and pushed
[ ] Job image built and pushed
[ ] API deployed
[ ] UI deployed
[ ] Job deployed
[ ] Required env vars set
[ ] Uploads bucket mounted to /uploads
[ ] UI configured with correct API URL
[ ] API CORS configured for UI origin
[ ] Health endpoint passes
[ ] Test run succeeds end-to-end
```

---

# 15. ⚠️ Known Migration-Sensitive Points

These are the most likely failure points during migration:

* wrong repo branch deployed
* stale API URL in UI
* stale UI origin in API CORS
* missing `/uploads` mount
* wrong bucket names
* missing required env vars
* Cloud Run Job name mismatch
* Firestore not created

---

# 16. 🧠 Deployment Principle

A migration is considered successful only when:

* a new run can be submitted
* the job executes successfully
* outputs appear in the runs bucket
* metadata is readable by the API
* UI can display results without direct GCS access

That is the definition of a working platform deployment.
