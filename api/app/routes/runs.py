from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from app.run_submission_service import submit_run

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
    return {
        "runs": [],
        "backend": "firestore",
        "status": "stubbed_not_implemented",
        "message": "Run listing will be backed by Firestore in a later step.",
    }


@router.get("/runs/{run_id}")
def get_run(run_id: str) -> dict:
    return {
        "run_id": run_id,
        "backend": "firestore",
        "status": "stubbed_not_implemented",
        "message": "Run lookup will be backed by Firestore in a later step.",
    }
