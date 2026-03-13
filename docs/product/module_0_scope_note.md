# Somatic Pipeline Cloud Dashboard v1 Scope Note

## Purpose

This document freezes the v1 product scope for the Somatic Pipeline Cloud Dashboard so implementation stays focused and does not sprawl.

## Primary User

Technical bioinformatics or research operator.

This user is comfortable with sequencing workflows, cloud execution concepts, and pipeline outputs, and needs a lightweight operational console rather than a clinician-facing application.

## v1 Goal

Build a lightweight cloud execution console for submitting, monitoring, and retrieving outputs from the Somatic Pipeline Harness.

The v1 dashboard should make it possible to launch a run, track its progress, inspect run metadata, and access final outputs without requiring direct manual interaction with the underlying cloud job system.

## In Scope

The v1 dashboard must support the following:

- register sample inputs or cloud input paths
- submit a pipeline run
- monitor run status
- view run metadata
- access the HTML report
- access logs
- access core output artifacts

## Out of Scope

The following are explicitly out of scope for v1:

- multi-user permissions
- clinician signoff workflows
- advanced genomics visualizations
- automated billing
- live websocket streaming
- notifications
- rich in-browser interpretation tools

These items may be considered in later phases, but they are not required for a successful v1 release.

## Success Criteria

Module 0 is considered complete when the team agrees that v1 success means all of the following:

- a user can create and submit a run
- the backend triggers cloud execution
- outputs are written to cloud storage
- metadata is recorded across the run lifecycle
- the dashboard shows a run list and run detail view
- completed runs expose report and artifact links
- at least one end-to-end run succeeds

## Product Stance

This product is a technical cloud execution console, not a clinical platform.

It is designed for operational use by technical users who need a clean interface for managing pipeline runs and retrieving outputs. Clinical workflow features, interpretation layers, and institutional governance features are intentionally excluded from v1.

## Go / No-Go Boundary for v1

A feature belongs in v1 only if it directly supports one of these actions:

1. submit a run
2. monitor a run
3. inspect metadata
4. retrieve outputs

If a proposed feature does not directly support one of these actions, it should be deferred to a later module or backlog.

## Module 0 Completion Proof

Module 0 is complete when this file exists at:

```text
docs/product/module_0_scope_note.md
