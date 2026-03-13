# Somatic Pipeline Harness Documentation

This directory contains architecture, operational, and development documentation
for the Somatic Pipeline Harness and Cloud Dashboard.

Main sections:

- product — scope and roadmap
- architecture — system design
- api — backend API contracts
- storage — cloud storage structure
- pipeline — pipeline outputs and metadata
- deployment — cloud deployment details
- operations — operational workflows
- development — developer setup




product/

Product definition and roadmap.

docs/product/

Contains:

module_0_scope_note.md
roadmap.md

This is where Module 0 lives.

architecture/

High-level system design.

docs/architecture/

Important documents:

system_architecture.md

Explains:

frontend

API

job execution

storage

metadata

run_lifecycle.md

Example states:

SUBMITTED
QUEUED
RUNNING
SUCCEEDED
FAILED
data_flow.md

Explains:

User → API → Cloud Run Job → Pipeline → Storage → Metadata → UI
api/

Backend API documentation.

docs/api/

Example:

endpoints.md
POST /runs
GET /runs
GET /runs/{run_id}
GET /runs/{run_id}/artifacts
run_schema.md

Defines Run object.

Example:

run_id
sample_id
status
submitted_at
started_at
finished_at
artifacts
storage/

Cloud storage contract.

docs/storage/

Example layout:

gs://somatic-pipeline/

inputs/<run_id>/
outputs/<run_id>/
reports/<run_id>/
logs/<run_id>/
manifests/<run_id>/
pipeline/

Pipeline output definitions.

docs/pipeline/

This describes what your harness produces.

Examples:

outputs.md
PASS.annotated.tsv
PASS.somaticish.tsv
PASS.germlineish.tsv
PASS.uncertain.tsv
gene_summary.tsv
report.html
run_manifest.md

Defines:

run_manifest.json
status.json
artifacts.json
deployment/

How the cloud system runs.

docs/deployment/

Examples:

cloud_run_jobs.md

Explains:

job configuration

environment variables

container images

runtime resources

docker_images.md

Explains:

pipeline container
api container
operations/

Operational guides.

docs/operations/

Example:

run_submission.md

Explains:

User submits run
API generates run_id
API triggers job
Pipeline writes artifacts
troubleshooting.md

Common failures:

pipeline failure
storage access failure
job timeout
missing references
development/

Developer guidance.

docs/development/

Examples:

repo_structure.md

Explains:

pipeline/
api/
ui/
infra/
docs/
local_development.md

How to run locally.

Why This Structure Is Good

This layout separates:

Category	Purpose
Product	scope and roadmap
Architecture	system design
API	backend contracts
Storage	cloud layout
Pipeline	pipeline outputs
Deployment	cloud infrastructure
Operations	how to run it
Development	how to build it

This is exactly how large research software projects organize docs.
