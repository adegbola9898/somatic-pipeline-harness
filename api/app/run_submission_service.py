"""Minimal run submission service for Module 6.

This first cut defines the shape of:
- run ID generation
- initial Firestore payload construction
- Cloud Run job launch request construction
- submit_run() orchestration wrapper
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, Optional
from uuid import uuid4

from app.clients.firestore_client import create_run_document, update_run_document
from app.clients.run_jobs_client import launch_job
from app.config import settings
import logging

logger = logging.getLogger("uvicorn.error")


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


def resolve_launch_env(
    request_payload: Optional[Dict[str, Any]],
    *,
    firestore_collection: str,
    runs_bucket: Optional[str],
    extra_env: Optional[Dict[str, str]],
) -> Dict[str, str]:
    request_payload = request_payload or {}

    env: Dict[str, str] = {
        "FIRESTORE_COLLECTION": firestore_collection,
        "UPLOADS_BUCKET": settings.uploads_bucket,
        "THREADS": str(settings.threads),
        "TARGETS_BED": settings.targets_bed,
    }

    if runs_bucket:
        env["RUNS_BUCKET"] = runs_bucket

    if request_payload.get("sra"):
        env["INPUT_MODE"] = "sra"
        env["SRA"] = str(request_payload["sra"])
    elif request_payload.get("fastq1") and request_payload.get("fastq2"):
        env["INPUT_MODE"] = "fastq_pair"
        env["FASTQ1"] = str(request_payload["fastq1"])
        env["FASTQ2"] = str(request_payload["fastq2"])

    if extra_env:
        env.update(extra_env)

    return env


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
    """Create the minimum orchestration shape for a submitted run."""
    resolved_run_id = run_id or generate_run_id()
    resolved_runs_bucket = settings.runs_bucket
    if not resolved_runs_bucket:
        raise RuntimeError("RUNS_BUCKET is not configured")

    logger.info(
        "submit_run.resolved_config %s",
        json.dumps(
            {
                "run_id": resolved_run_id,
                "runs_bucket": resolved_runs_bucket,
                "uploads_bucket": settings.uploads_bucket,
                "input_mode": (
                    "sra" if (request_payload or {}).get("sra")
                    else "fastq_pair" if (request_payload or {}).get("fastq1") else "unknown"
                ),
            },
            sort_keys=True,
        ),
    )

    
    input_mode = (
        "sra" if (request_payload or {}).get("sra")
        else "fastq_pair" if (request_payload or {}).get("fastq1") else "unknown"
    )

    firestore_payload = build_initial_run_payload(
        resolved_run_id,
        request_payload=request_payload,
        status="submitted",
        firestore_collection=firestore_collection,
    )

    
    # enrich payload with resolved config
    firestore_payload.update({
        "input_mode": input_mode,
        "runs_bucket": resolved_runs_bucket,
        "uploads_bucket": settings.uploads_bucket,
    })

    create_run_document(
        firestore_collection,
        resolved_run_id,
        firestore_payload,
    )

    launch_env = resolve_launch_env(
        request_payload,
        firestore_collection=firestore_collection,
        runs_bucket=resolved_runs_bucket,
        extra_env=extra_env,
    )

    job_launch_request = build_job_launch_request(
        resolved_run_id,
        job_name=job_name,
        runs_bucket=resolved_runs_bucket,
        firestore_collection=firestore_collection,
        extra_env=launch_env,
    )

    launch_result = launch_job(
        job_name=job_name,
        run_id=resolved_run_id,
        env_vars=launch_env,
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
