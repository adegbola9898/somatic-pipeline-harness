# 🔐 IAM & Permissions

This document defines the service accounts and permissions required by the Somatic Pipeline Platform.

It ensures that:

* each component has the minimum required access
* permissions are explicit and reproducible
* migrations across projects do not break due to missing IAM bindings

---

# 1. 🧱 Overview

The platform uses separate identities for:

* API service (control plane)
* Job runner (execution plane)

Each identity must have **only the permissions it needs**.

---

# 2. 👤 Service Accounts

## 2.1 API Service Account

```text
Name: api-sa
Used by: Cloud Run API service
```

### Responsibilities

* Accept run submissions
* Write/read Firestore
* Launch Cloud Run Jobs
* Read artifacts from GCS

---

## 2.2 Job Service Account

```text
Name: job-sa
Used by: Cloud Run Job (pipeline runner)
```

### Responsibilities

* Execute pipeline
* Read input data from uploads bucket
* Write outputs to runs bucket
* Update Firestore state

---

# 3. 📦 Required Permissions

## 3.1 API Service Account Permissions

### Firestore

```text
roles/datastore.user
```

Allows:

* create run documents
* update run state
* read run metadata

---

### Cloud Run Job Execution

```text
roles/run.invoker
```

Allows:

* API to trigger Cloud Run Jobs

---

### GCS (Read Access)

```text
roles/storage.objectViewer
```

Allows:

* read artifacts
* read metadata files

---

## 3.2 Job Service Account Permissions

### GCS (Runs Bucket - Write)

```text
roles/storage.objectAdmin
```

Allows:

* upload results
* write metadata
* write logs

---

### GCS (Uploads Bucket - Read)

```text
roles/storage.objectViewer
```

Allows:

* read FASTQ files

---

### Firestore

```text
roles/datastore.user
```

Allows:

* update run state
* write failure status
* finalize metadata

---

### Logging

```text
roles/logging.logWriter
```

Allows:

* write logs to Cloud Logging

---

# 4. 🔗 Resource Binding Matrix

| Resource       | API SA          | Job SA     |
| -------------- | --------------- | ---------- |
| Firestore      | read/write      | read/write |
| Runs Bucket    | read            | write      |
| Uploads Bucket | read (optional) | read       |
| Cloud Run Job  | invoke          | execute    |
| Logging        | optional        | required   |

---

# 5. ⚙️ Example IAM Commands

## Create service accounts

```bash
gcloud iam service-accounts create api-sa
gcloud iam service-accounts create job-sa
```

---

## Grant API permissions

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:api-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:api-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.invoker"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:api-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

---

## Grant Job permissions

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:job-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:job-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:job-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:job-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"
```

---

# 6. 🔁 Service Attachment

## API

Attach service account during deployment:

```bash
gcloud run deploy somatic-pipeline-api \
  --service-account api-sa@$PROJECT_ID.iam.gserviceaccount.com
```

---

## Job

Attach service account during deployment:

```bash
gcloud run jobs deploy somatic-pipeline-runner \
  --service-account job-sa@$PROJECT_ID.iam.gserviceaccount.com
```

---

# 7. ⚠️ Common IAM Failure Modes

| Issue                      | Cause                          |
| -------------------------- | ------------------------------ |
| Job not launching          | API lacks run.invoker          |
| Firestore writes fail      | missing datastore.user         |
| FASTQ not found            | job lacks storage.objectViewer |
| Upload fails               | job lacks storage.objectAdmin  |
| Logs missing               | missing logging.logWriter      |
| API cannot serve artifacts | missing storage.objectViewer   |

---

# 8. 🧠 Design Principle

Each component must have:

* **minimum required permissions**
* **no shared service accounts**
* **explicit IAM bindings**

This ensures:

* security
* auditability
* portability across projects

---

# 9. 🚀 Migration Rule

During migration, IAM must be recreated before deployment.

Checklist:

```text
[ ] api-sa created
[ ] job-sa created
[ ] API permissions granted
[ ] Job permissions granted
[ ] API deployed with api-sa
[ ] Job deployed with job-sa
```

If IAM is incorrect, the system will fail silently.
