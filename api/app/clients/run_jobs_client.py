from __future__ import annotations

from typing import Any, Dict, Optional

import google.auth
from google.auth.transport.requests import AuthorizedSession

from app.config import settings

def launch_job(
    *,
    job_name: str,
    run_id: str,
    region: Optional[str] = None,
    project_id: Optional[str] = None,
) -> Dict[str, Any]:
    resolved_project = project_id or settings.project_id
    resolved_region = region or settings.region

    url = (
        f"https://run.googleapis.com/v2/projects/{resolved_project}/locations/"
        f"{resolved_region}/jobs/{job_name}:run"
    )

    body = {
        "overrides": {
            "containerOverrides": [
                {
                    "env": [
                        {"name": "RUN_ID", "value": run_id},
                    ]
                }
            ]
        }
    }

    creds, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    session = AuthorizedSession(creds)
    response = session.post(url, json=body)
    response.raise_for_status()

    payload = response.json()
    metadata = payload.get("metadata", {})

    return {
        "operation_name": payload.get("name"),
        "execution_name": metadata.get("name"),
        "job_name": metadata.get("job"),
        "region": resolved_region,
        "project_id": resolved_project,
        "response": payload,
    }
