# ADR 0001 — API-First Architecture

## Status
Accepted

## Context

The Somatic Pipeline Cloud Dashboard requires a backend service
to submit and monitor pipeline runs.

The system could be implemented either as:

1. A combined UI and backend application
2. A separate API backend with a lightweight UI layer

## Decision

The system will adopt an API-first architecture.

The API service will:

- expose run submission endpoints
- manage run metadata
- trigger Cloud Run Jobs
- provide status queries

The API will also serve simple HTML pages in v1.

## Consequences

Benefits:

- clear separation between execution logic and UI
- easier future expansion to richer frontends
- easier automation and scripting via API

Tradeoffs:

- slightly more structure than a simple web UI



Large projects accumulate many ADRs like:

docs/adr/
0001-api-first-architecture.md
0002-cloud-run-jobs-execution.md
0003-firestore-run-metadata.md
0004-storage-layout-contract.md

This is very common in production systems.
