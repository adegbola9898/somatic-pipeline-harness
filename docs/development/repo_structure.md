# Repository Structure

## Purpose

This document defines the repository layout for the Somatic Pipeline Harness and Cloud Dashboard.

The goal is to keep pipeline execution, API orchestration, frontend work, infrastructure, and documentation clearly separated.

---

# Top-Level Layout

```
somatic-pipeline-harness/

├── api/            # backend orchestration service
├── bin/            # pipeline execution scripts
├── docker/         # development container definitions
├── docs/           # product, architecture, and operational documentation
├── env/            # reproducible environment configuration
├── infra/          # cloud deployment and infrastructure definitions
├── tests/          # integration and validation tests
├── ui/             # reserved for future standalone frontend
└── ui_prototype/   # archived prototype dashboard
```

---

# Directory Responsibilities

## api/

Contains the backend service.

This service is responsible for:

- creating runs  
- retrieving run metadata  
- launching Cloud Run Jobs  
- resolving artifact links  
- serving simple dashboard pages in v1  

The API is implemented as an explicit Python package under:

```
api/app/
```

with stable ASGI entrypoint:

```
app.main:app
```

---

## bin/

Contains the pipeline execution harness.

Primary entrypoint:

```
bin/run_somatic_pipeline.sh
```

The pipeline must remain independent of:

- Firestore  
- API request handling  
- Cloud Run service logic  

It should only read inputs, execute analysis, and write outputs.

---

## ui/

Reserved for a future standalone frontend.

For v1, the API may serve simple HTML pages directly.

---

## ui_prototype/

Archived prototype UI code retained for reference.

This directory is not the long-term architectural boundary for the product.

---

## infra/

Contains cloud deployment and infrastructure definitions.

Expected areas include:

- Cloud Run  
- GCS  
- IAM  
- Firestore  

---

## docs/

Contains product, architecture, storage, deployment, and development documentation.

---

## env/

Contains reproducible environment configuration for development.

---

## tests/

Reserved for validation, integration tests, and future hardening.

---

# API Package Structure Rule

The API must remain an explicit Python package.

Required package markers:

- `api/app/__init__.py`
- `api/app/routes/__init__.py`
- `api/app/services/__init__.py`
- `api/app/clients/__init__.py`
- `api/app/models/__init__.py`

This prevents local-versus-container import ambiguity.

---

# Runtime Entry Point Rule

The API must use a single stable entrypoint everywhere.

Local development example:

```
uvicorn app.main:app --host 0.0.0.0 --port 8080
```

Docker / Cloud Run entrypoint:

```
uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}
```

---

# Run ID Convention

All platform-level runs must use a shared run ID format:

```
run_<timestamp>_<random>
```

Example:

```
run_20260313_153022_ab12
```

Properties:

- globally unique  
- sortable by time  
- filesystem-safe  
- URL-safe  

Run IDs will be used in:

- API responses  
- Cloud Storage paths  
- job arguments  
- manifests  
- metadata records  

---

# Development Rule

Cloud platform logic must live in the API and infrastructure layers.

Pipeline logic must remain runnable independently of the cloud platform.
