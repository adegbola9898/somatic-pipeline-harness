"""Minimal run submission service for Module 6.

This first cut defines the shape of:
- run ID generation
- initial Firestore payload construction
- Cloud Run job launch request construction
- submit_run() orchestration wrapper

External integrations remain stubbed for now so the module can be
wired incrementally without forcing framework or client decisions.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, Optional
from uuid import uuid4
from app.clients.firestore_client import create_run_document, update_run_document
from app.clients.run_jobs_client import launch_job


DEFAULT_FIRESTORE_COLLECTION = "runs"
DEFAULT_JOB_NAME = "somatic-pipeline-runner"


def utc_now_iso() -> str:
    """Return the current UTC timestamp in ISO-8601 format."""
    return datetime.now(timezone.utc).isoformat()


def generate_run_id(prefix: str = "run") -> str:
    """Generate a run identifier suitable for Firestore and job correlation."""
    return f"{prefix}-{uuid4().hex[:12]}"


def build_initial_run_payload(
    run_id: str,
    request_payload: Optional[Dict[str, Any]] = None,
    *,
    status: str = "submitted",
    firestore_collection: str = DEFAULT_FIRESTORE_COLLECTION,
) -> Dict[str, Any]:
    """Build the initial Firestore payload for a newly submitted run."""
    request_payload = request_payload or {}

    return {
        "run_id": run_id,
        "status": status,
        "metadata_finalized": False,
        "created_at": utc_now_iso(),
        "updated_at": utc_now_iso(),
        "firestore_collection": firestore_collection,
        "request": request_payload,
    }


def build_job_launch_request(
    run_id: str,
    *,
    job_name: str = DEFAULT_JOB_NAME,
    runs_bucket: Optional[str] = None,
    firestore_collection: str = DEFAULT_FIRESTORE_COLLECTION,
    extra_env: Optional[Dict[str, str]] = None,
) -> Dict[str, Any]:
    """Build a minimal Cloud Run Job launch request shape."""
    env = {
        "RUN_ID": run_id,
        "FIRESTORE_COLLECTION": firestore_collection,
    }

    if runs_bucket:
        env["RUNS_BUCKET"] = runs_bucket

    if extra_env:
        env.update(extra_env)

    return {
        "job_name": job_name,
        "overrides": {
            "container_overrides": [
                {
                    "env": [{"name": key, "value": value} for key, value in sorted(env.items())]
                }
            ]
        },
    }


@dataclass
class SubmitRunResult:
    run_id: str
    firestore_payload: Dict[str, Any]
    job_launch_request: Dict[str, Any]
    firestore_write_status: str
    job_launch_status: str


def submit_run(
    request_payload: Optional[Dict[str, Any]] = None,
    *,
    run_id: Optional[str] = None,
    runs_bucket: Optional[str] = None,
    firestore_collection: str = DEFAULT_FIRESTORE_COLLECTION,
    job_name: str = DEFAULT_JOB_NAME,
    extra_env: Optional[Dict[str, str]] = None,
) -> SubmitRunResult:
    """Create the minimum orchestration shape for a submitted run.

    This function intentionally does not call Firestore or Cloud Run yet.
    It returns the payloads that later wiring will persist and execute.
    """
    resolved_run_id = run_id or generate_run_id()

    firestore_payload = build_initial_run_payload(
        resolved_run_id,
        request_payload=request_payload,
        status="submitted",
        firestore_collection=firestore_collection,
    )

    create_run_document(
        firestore_collection,
        resolved_run_id,
        firestore_payload,
    )

    job_launch_request = build_job_launch_request(
        resolved_run_id,
        job_name=job_name,
        runs_bucket=runs_bucket,
        firestore_collection=firestore_collection,
        extra_env={
            **(extra_env or {}),
            **({"SRA": request_payload.get("sra")} if request_payload and request_payload.get("sra") else {})
        },
    )

    launch_result = launch_job(
        job_name=job_name,
        run_id=resolved_run_id,
        env_vars={
            **(extra_env or {}),
            **({"SRA": request_payload.get("sra")} if request_payload and request_payload.get("sra") else {}),
        },
    )

    execution_name = launch_result.get("execution_name")

    if execution_name:
        update_run_document(
            firestore_collection,
            resolved_run_id,
            {
                "execution_name": execution_name,
                "updated_at": utc_now_iso(),
            },
        )

    return SubmitRunResult(
        run_id=resolved_run_id,
        firestore_payload=firestore_payload,
        job_launch_request=job_launch_request,
        firestore_write_status="written",
        job_launch_status="launched",
    )
