from __future__ import annotations

import os
from typing import Any, Dict, Optional

from fastapi import APIRouter
from fastapi.responses import HTMLResponse, Response
from pydantic import BaseModel, Field, model_validator

from app.run_submission_service import submit_run
from app.clients.firestore_client import list_run_documents, get_run_document
from app.clients.gcs_client import read_run_metadata, get_run_report_uri, get_run_qc_uri, download_blob_bytes, get_run_report_blob, get_run_qc_blob_paths, normalize_run_blob_path

router = APIRouter(tags=["runs"])


class RunCreateRequest(BaseModel):
    runs_bucket: Optional[str] = Field(default=None, description="Target runs bucket")
    request: Dict[str, Any] = Field(default_factory=dict, description="Run request payload")
    extra_env: Dict[str, str] = Field(default_factory=dict, description="Optional extra env overrides")

    @model_validator(mode="after")
    def validate_request_payload(self) -> "RunCreateRequest":
        request = self.request or {}

        has_sra = bool(request.get("sra"))
        has_fastq1 = bool(request.get("fastq1"))
        has_fastq2 = bool(request.get("fastq2"))

        if has_sra and (has_fastq1 or has_fastq2):
            raise ValueError("Do not provide 'sra' together with 'fastq1'/'fastq2'.")

        if has_sra:
            return self

        if has_fastq1 != has_fastq2:
            raise ValueError("FASTQ mode requires both 'fastq1' and 'fastq2'.")

        if has_fastq1 and has_fastq2:
            return self

        raise ValueError(
            "Exactly one input mode must be provided: either 'sra' or both 'fastq1' and 'fastq2'."
        )


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
    # normalize failure fields for external contract
    runs = []
    for r in result["runs"]:
        r = dict(r)

        if r.get("status") == "failed":
            r["failure_stage"] = r.get("failed_step")
            r["failure_code"] = r.get("failure_category")
            r["failure_message"] = r.get("failure_reason")
            if r.get("failure_category"):
                r["retryable"] = r.get("failure_category") != "entrypoint_validation"
            else:
                r["retryable"] = None

        runs.append(r)

    return {
        "runs": runs,
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

    run = dict(result["run"] or {})

    if run.get("status") == "failed":
        run["failure_stage"] = run.get("failed_step")
        run["failure_code"] = run.get("failure_category")
        run["failure_message"] = run.get("failure_reason")
        if run.get("failure_category"):
            run["retryable"] = run.get("failure_category") != "entrypoint_validation"
        else:
            run["retryable"] = None

    return {
        "run_id": run_id,
        "run": run,
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
    except Exception as e:
        return {
            "run_id": run_id,
            "status": "report_not_found",
            "backend": "gcs",
            "error": str(e),
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
    except Exception as e:
        return {
            "run_id": run_id,
            "status": "qc_not_found",
            "backend": "gcs",
            "error": str(e),
        }

    return {
        "run_id": run_id,
        "qc": result,
        "backend": "gcs",
        "status": "ok",
    }


@router.get("/runs/{run_id}/report/content")
def get_run_report_content(run_id: str):
    try:
        result = get_run_report_blob(run_id)
        content = download_blob_bytes(result["bucket"], result["blob_path"])
    except Exception as e:
        return {
            "run_id": run_id,
            "status": "report_content_not_found",
            "backend": "gcs",
            "error": str(e),
        }

    return Response(content=content, media_type=result["content_type"])


@router.get("/runs/{run_id}/qc/stdout")
def get_run_stdout_content(run_id: str):
    try:
        result = get_run_qc_blob_paths(run_id)
        blob_path = result.get("stdout_blob_path")
        if not blob_path:
            raise FileNotFoundError(f"stdout log path missing for run_id={run_id}")
        content = download_blob_bytes(result["bucket"], blob_path)
    except Exception as e:
        return {
            "run_id": run_id,
            "status": "stdout_not_found",
            "backend": "gcs",
            "error": str(e),
        }

    return Response(content=content, media_type="text/plain; charset=utf-8")


@router.get("/runs/{run_id}/qc/stderr")
def get_run_stderr_content(run_id: str):
    try:
        result = get_run_qc_blob_paths(run_id)
        blob_path = result.get("stderr_blob_path")
        if not blob_path:
            raise FileNotFoundError(f"stderr log path missing for run_id={run_id}")
        content = download_blob_bytes(result["bucket"], blob_path)
    except Exception as e:
        return {
            "run_id": run_id,
            "status": "stderr_not_found",
            "backend": "gcs",
            "error": str(e),
        }

    return Response(content=content, media_type="text/plain; charset=utf-8")


@router.get("/runs/{run_id}/artifacts/download")
def download_run_artifact(run_id: str, path: str):
    try:
        metadata = read_run_metadata(run_id)
        bucket = metadata["bucket"]
        blob_path = f"runs/{run_id}/{normalize_run_blob_path(path)}"
        content = download_blob_bytes(bucket, blob_path)
        filename = os.path.basename(path)
    except Exception as e:
        return {
            "run_id": run_id,
            "status": "artifact_not_found",
            "backend": "gcs",
            "error": str(e),
        }

    return Response(
        content=content,
        media_type="application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
