from __future__ import annotations

import json
from typing import Any, Dict

from google.cloud import storage

from app.config import settings


def get_client() -> storage.Client:
    return storage.Client(project=settings.project_id)


def read_json_blob(bucket_name: str, blob_path: str) -> Dict[str, Any]:
    client = get_client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(blob_path)

    if not blob.exists():
        raise FileNotFoundError(f"gs://{bucket_name}/{blob_path} not found")

    text = blob.download_as_text()
    return json.loads(text)


def read_run_metadata(run_id: str, bucket_name: str | None = None) -> Dict[str, Any]:
    resolved_bucket = bucket_name or settings.runs_bucket
    if not resolved_bucket:
        raise ValueError("runs bucket is not configured")

    base = f"runs/{run_id}/metadata"

    return {
        "run_manifest": read_json_blob(resolved_bucket, f"{base}/run_manifest.json"),
        "status": read_json_blob(resolved_bucket, f"{base}/status.json"),
        "artifacts": read_json_blob(resolved_bucket, f"{base}/artifacts.json"),
        "bucket": resolved_bucket,
        "run_id": run_id,
    }


def build_gcs_uri(bucket_name: str, blob_path: str) -> str:
    return f"gs://{bucket_name}/{blob_path}"


def get_run_report_uri(run_id: str, bucket_name: str | None = None) -> Dict[str, str]:
    metadata = read_run_metadata(run_id, bucket_name)
    resolved_bucket = metadata["bucket"]
    artifacts = metadata.get("artifacts") or {}
    report_path = artifacts.get("report_html_path")

    if not report_path:
        raise FileNotFoundError(f"report path missing for run_id={run_id}")

    blob_path = f"runs/{run_id}/{normalize_run_blob_path(report_path)}"
    return {
        "run_id": run_id,
        "bucket": resolved_bucket,
        "report_path": report_path,
        "report_uri": build_https_url(resolved_bucket, blob_path),
    }


def get_run_qc_uri(run_id: str, bucket_name: str | None = None) -> Dict[str, str]:
    metadata = read_run_metadata(run_id, bucket_name)
    resolved_bucket = metadata["bucket"]
    artifacts = metadata.get("artifacts") or {}

    stderr_log_path = artifacts.get("stderr_log_path")
    stdout_log_path = artifacts.get("stdout_log_path")

    result = {
        "run_id": run_id,
        "bucket": resolved_bucket,
    }

    if stdout_log_path:
        result["stdout_log_path"] = stdout_log_path
        result["stdout_log_uri"] = build_https_url(resolved_bucket, f"runs/{run_id}/{stdout_log_path}")

    if stderr_log_path:
        result["stderr_log_path"] = stderr_log_path
        result["stderr_log_uri"] = build_https_url(resolved_bucket, f"runs/{run_id}/{stderr_log_path}")

    return result


def build_https_url(bucket_name: str, blob_path: str) -> str:
    return f"https://storage.googleapis.com/{bucket_name}/{blob_path}"


def download_blob_bytes(bucket_name: str, blob_path: str) -> bytes:
    client = get_client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(blob_path)

    if not blob.exists():
        raise FileNotFoundError(f"gs://{bucket_name}/{blob_path} not found")

    return blob.download_as_bytes()


def get_run_report_blob(run_id: str, bucket_name: str | None = None) -> Dict[str, str]:
    metadata = read_run_metadata(run_id, bucket_name)
    resolved_bucket = metadata["bucket"]
    artifacts = metadata.get("artifacts") or {}
    report_path = artifacts.get("report_html_path")

    if not report_path:
        raise FileNotFoundError(f"report path missing for run_id={run_id}")

    return {
        "run_id": run_id,
        "bucket": resolved_bucket,
        "blob_path": f"runs/{run_id}/{normalize_run_blob_path(report_path)}",
        "content_type": "text/html; charset=utf-8",
    }


def get_run_qc_blob_paths(run_id: str, bucket_name: str | None = None) -> Dict[str, str]:
    metadata = read_run_metadata(run_id, bucket_name)
    resolved_bucket = metadata["bucket"]
    artifacts = metadata.get("artifacts") or {}

    result = {
        "run_id": run_id,
        "bucket": resolved_bucket,
    }

    stdout_log_path = artifacts.get("stdout_log_path")
    stderr_log_path = artifacts.get("stderr_log_path")

    if stdout_log_path:
        result["stdout_blob_path"] = f"runs/{run_id}/{stdout_log_path}"

    if stderr_log_path:
        result["stderr_blob_path"] = f"runs/{run_id}/{stderr_log_path}"

    return result


def normalize_run_blob_path(path: str) -> str:
    if path.startswith("results/reports/"):
        return path.replace("results/reports/", "reports/", 1)
    if path.startswith("results/mutect2/"):
        return path.replace("results/mutect2/", "outputs/mutect2/", 1)
    return path
