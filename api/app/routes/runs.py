from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from app.run_submission_service import submit_run
from app.clients.firestore_client import list_run_documents, get_run_document
from app.clients.gcs_client import read_run_metadata, get_run_report_uri, get_run_qc_uri

router = APIRouter(tags=["runs"])


class RunCreateRequest(BaseModel):
    runs_bucket: Optional[str] = Field(default=None, description="Target runs bucket")
    request: Dict[str, Any] = Field(default_factory=dict, description="Opaque run request payload")
    extra_env: Dict[str, str] = Field(default_factory=dict, description="Optional extra env overrides")


@router.get("/", response_class=HTMLResponse)
def index() -> str:
    return """
    <html>
      <body style="font-family: Arial; margin: 40px;">
        <h2>Somatic Pipeline API</h2>
        <p>API skeleton is live.</p>
        <ul>
          <li><a href="/health">Health check</a></li>
          <li><a href="/runs">Runs endpoint</a></li>
        </ul>
      </body>
    </html>
    """


@router.post("/runs")
def create_run(payload: RunCreateRequest) -> dict:
    result = submit_run(
        request_payload=payload.request,
        runs_bucket=payload.runs_bucket,
        extra_env=payload.extra_env,
    )

    return {
        "run_id": result.run_id,
        "status": result.firestore_payload["status"],
        "metadata_finalized": result.firestore_payload["metadata_finalized"],
        "firestore_write_status": result.firestore_write_status,
        "job_launch_status": result.job_launch_status,
        "firestore_payload": result.firestore_payload,
        "job_launch_request": result.job_launch_request,
    }


@router.get("/runs")
def list_runs() -> dict:
    result = list_run_documents("runs", limit=50)
    return {
        "runs": result["runs"],
        "count": result["count"],
        "backend": "firestore",
        "status": "ok",
    }


@router.get("/runs/{run_id}")
def get_run(run_id: str) -> dict:
    result = get_run_document("runs", run_id)

    if not result["exists"]:
        return {
            "run_id": run_id,
            "status": "not_found",
            "backend": "firestore",
        }

    metadata = None
    try:
        metadata = read_run_metadata(run_id)
    except Exception:
        metadata = None

    return {
        "run_id": run_id,
        "run": result["run"],
        "metadata": metadata,
        "backend": "firestore",
        "status": "ok",
    }


@router.get("/runs/{run_id}/artifacts")
def get_run_artifacts(run_id: str) -> dict:
    try:
        metadata = read_run_metadata(run_id)
    except Exception:
        return {
            "run_id": run_id,
            "status": "metadata_not_found",
            "backend": "gcs",
        }

    return {
        "run_id": run_id,
        "artifacts": metadata["artifacts"],
        "backend": "gcs",
        "status": "ok",
    }


@router.get("/runs/{run_id}/report")
def get_run_report(run_id: str) -> dict:
    try:
        result = get_run_report_uri(run_id)
    except Exception:
        return {
            "run_id": run_id,
            "status": "report_not_found",
            "backend": "gcs",
        }

    return {
        "run_id": run_id,
        "report": result,
        "backend": "gcs",
        "status": "ok",
    }


@router.get("/runs/{run_id}/qc")
def get_run_qc(run_id: str) -> dict:
    try:
        result = get_run_qc_uri(run_id)
    except Exception:
        return {
            "run_id": run_id,
            "status": "qc_not_found",
            "backend": "gcs",
        }

    return {
        "run_id": run_id,
        "qc": result,
        "backend": "gcs",
        "status": "ok",
    }
