# System Architecture

## Overview

The Somatic Pipeline Cloud Dashboard is built as a modular cloud execution
system that separates user interaction, job orchestration, pipeline execution,
and artifact storage.

The system architecture consists of the following components:

- Frontend Dashboard
- Backend API
- Job Submission Layer
- Cloud Run Jobs
- Firestore
- Cloud Storage
- Artifact Registry

## Architecture Diagram

![System Architecture](../../architecture_diagram.png))

## Component Responsibilities

### Frontend Dashboard

User-facing interface responsible for:

- submitting runs
- displaying run status
- presenting run metadata
- linking to pipeline outputs

### Backend API

Handles:

- run creation
- run lookup
- metadata management
- job submission

The API acts as the orchestration layer between the UI and pipeline execution.

### Job Submission Layer

Responsible for launching Cloud Run Jobs with the correct configuration and
runtime arguments.

### Cloud Run Jobs

Executes the somatic pipeline container.

The job:

- reads inputs and references
- runs the pipeline
- writes outputs and logs
- updates run status

### Firestore

Stores run metadata and lifecycle state.

Acts as the source of truth for:

- run status
- run timestamps
- artifact locations

### Cloud Storage

Stores pipeline inputs and outputs including:

- reference bundles
- uploaded data
- run outputs
- logs
- HTML reports

### Artifact Registry

Stores the pipeline container images used by Cloud Run Jobs.
