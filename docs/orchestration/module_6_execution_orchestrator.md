# Module 6 — Run Execution Orchestrator

## Purpose

This module implements the runtime orchestration path shown in the platform architecture:

- Backend API creates a run record in Firestore
- Backend API launches a Cloud Run Job
- Cloud Run Job runs the pipeline harness
- Cloud Run Job runs the uploader
- Firestore is updated through lifecycle transitions
- `metadata_finalized=true` is written only after storage metadata exists

This module implements the control flow that connects the existing pipeline, uploader, and platform contracts.

---

## Scope

Module 6 includes the minimum orchestration path required to execute a run through the cloud platform.

Planned deliverables:

- `docs/orchestration/module_6_execution_orchestrator.md`
- `api/run_submission_service.py`
- `api/routes/runs.py`
- `bin/cloud_run_job_entrypoint.sh`
- `infra/cloud_run_job.yaml`

---

## Locked Inputs

This module must preserve the following existing decisions:

- pipeline entrypoint remains `bin/run_somatic_pipeline.sh`
- uploader entrypoint remains `bin/upload_run_to_cloud.sh`
- Firestore is the control plane
- Cloud Storage metadata is the durable metadata plane
- `metadata/artifacts.json` is authoritative for artifact discovery
- API must not scan buckets
- metadata uploads happen after data artifacts
- `metadata_finalized=true` is only allowed after metadata files exist in storage

---

## Runtime Flow

```mermaid
sequenceDiagram

participant UI
participant API
participant Firestore
participant Submit as Job Submission Layer
participant CloudRun
participant Pipeline
participant Uploader
participant Storage

UI->>API: POST /runs
API->>Firestore: create run (status=submitted)
API->>Submit: launch job

Submit->>CloudRun: execute job with run args
CloudRun->>Firestore: status=starting
CloudRun->>Firestore: status=running

CloudRun->>Pipeline: run pipeline harness
Pipeline->>Pipeline: generate run-root outputs

CloudRun->>Uploader: upload run outputs
Uploader->>Storage: upload data artifacts
Uploader->>Storage: upload metadata last

CloudRun->>Firestore: status=succeeded|failed
CloudRun->>Firestore: metadata_finalized=true only after metadata upload
Control Plane vs Durable Metadata Plane

Firestore stores live operational state for an in-flight or recently completed run.

Examples:

run identity

submission time

execution status

error state

Cloud Run execution references

finalization flags

Cloud Storage stores the durable artifact metadata plane.

Examples:

metadata/artifacts.json

other metadata files produced by the harness or uploader

immutable artifact references used by downstream readers

Firestore is used for orchestration and status reads.

Cloud Storage metadata is used for durable artifact discovery.

Run Lifecycle Expectations

Minimum expected lifecycle states for this module:

submitted

starting

running

succeeded

failed

This module should follow the existing run lifecycle and finalization contract already defined elsewhere in the repository.

metadata_finalized is not a substitute for execution status.

It is an additional guarantee that storage metadata publication completed successfully.

Backend API Responsibilities

The Backend API is responsible for:

accepting POST /runs

generating a new run identifier

creating the initial Firestore run record

launching the Cloud Run Job with run-specific arguments

returning the submitted run record to the caller

serving Firestore-backed run status reads

The API must not scan Cloud Storage to discover artifacts.

The API should rely on Firestore for live state and on metadata files for artifact-level discovery.

Job Submission Responsibilities

The job submission layer is responsible for translating the API submission request into a Cloud Run Job execution request.

Responsibilities include:

passing required environment variables and run arguments

referencing the correct job definition

preserving run identity across API, Firestore, Cloud Run, and storage paths

returning execution identifiers where available

This layer may start as a small helper and grow later without changing the API contract.

Cloud Run Job Responsibilities

The Cloud Run Job is responsible for runtime orchestration, not for changing platform contracts.

Responsibilities:

validate required environment variables

mark the run as starting and then running

invoke bin/run_somatic_pipeline.sh

invoke bin/upload_run_to_cloud.sh

update Firestore with terminal execution state

set metadata_finalized=true only after metadata files are confirmed uploaded

The Cloud Run Job is the component that bridges execution and publication.

Pipeline Harness Responsibilities

The pipeline harness entrypoint remains:

bin/run_somatic_pipeline.sh

Responsibilities:

execute the somatic pipeline

write outputs into the run workspace

produce the expected run-root artifact structure

produce metadata expected by the uploader and downstream contracts

The harness does not define storage publication semantics.

The harness is upstream of the uploader.

Uploader Responsibilities

The uploader entrypoint remains:

bin/upload_run_to_cloud.sh

Responsibilities:

publish run outputs from the run workspace to Cloud Storage

upload data artifacts before metadata artifacts

upload metadata files after data artifacts

ensure metadata needed for artifact discovery is present before finalization is allowed

Uploader behavior must remain aligned with Module 4 storage contract decisions.

Finalization Rules

This module must preserve the finalization ordering defined earlier in the project.

Required ordering:

pipeline execution reaches terminal outcome

uploader publishes data artifacts

uploader publishes metadata files

storage contains metadata/artifacts.json and required metadata files

Firestore is updated to terminal run status

metadata_finalized=true may be written

This ordering prevents Firestore from claiming finalization before durable metadata exists.

Artifact Discovery Rules

Artifact discovery is metadata-driven.

Authoritative source:

metadata/artifacts.json

Rules:

API must not scan buckets

bucket listing is not part of the authoritative read path

artifact detail returned by the API should be derived from metadata files, not inferred from storage prefixes

downstream readers should treat metadata as the source of truth for artifact enumeration

Failure Semantics

Failure handling must preserve contract clarity.

If the pipeline fails before upload:

Firestore ends in failed

metadata_finalized=true must not be set

If the pipeline produces partial outputs and uploader still publishes logs or metadata:

Firestore may still end in failed

metadata_finalized=true is allowed only if required metadata files exist in storage

If upload fails after pipeline execution:

Firestore ends in failed

finalization must remain incomplete unless metadata publication completed

A failed run may still have useful logs or partial artifacts, but finalization claims must remain accurate.

Minimum Runtime Inputs

Expected runtime inputs for the Cloud Run Job will likely include:

RUN_ID

RUNS_BUCKET

pipeline or workspace configuration values

any project or environment identifiers needed for Firestore and Cloud Run integration

Exact variable names may be refined in implementation, but the orchestration contract is that the job receives enough context to:

identify the run

execute the pipeline

upload outputs

finalize Firestore state correctly

Verification Goals

This document is complete enough for Module 6 implementation if it clearly answers:

who creates the run record

who launches the Cloud Run Job

who runs the pipeline

who runs the uploader

where live state is stored

where durable artifact metadata is stored

when terminal status is written

when metadata_finalized=true is allowed

Summary

Module 6 wires the execution path from API submission to durable run publication.

The Backend API creates the run and launches execution.

The Cloud Run Job performs orchestration of pipeline execution and upload.

Firestore remains the live control plane.

Cloud Storage metadata remains the durable metadata plane.

Finalization is only valid after storage metadata exists, preserving the artifact discovery contract.
