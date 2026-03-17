from __future__ import annotations

from typing import Any, Dict

from google.cloud import firestore

from app.config import settings


def get_client() -> firestore.Client:
    return firestore.Client(project=settings.project_id)


def create_run_document(collection: str, run_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_client()
    doc_ref = client.collection(collection).document(run_id)
    doc_ref.set(payload)
    return {
        "collection": collection,
        "document_id": run_id,
        "path": doc_ref.path,
        "project_id": client.project,
    }
