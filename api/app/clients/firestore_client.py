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


def update_run_document(collection: str, run_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_client()
    doc_ref = client.collection(collection).document(run_id)
    doc_ref.set(payload, merge=True)
    return {
        "collection": collection,
        "document_id": run_id,
        "path": doc_ref.path,
        "project_id": client.project,
    }


def list_run_documents(collection: str, limit: int = 100) -> Dict[str, Any]:
    client = get_client()
    docs = client.collection(collection).limit(limit).stream()
    runs = []
    for doc in docs:
        payload = doc.to_dict() or {}
        runs.append(payload)
    return {
        "collection": collection,
        "count": len(runs),
        "runs": runs,
        "project_id": client.project,
    }


def get_run_document(collection: str, run_id: str) -> Dict[str, Any]:
    client = get_client()
    doc_ref = client.collection(collection).document(run_id)
    doc = doc_ref.get()
    payload = doc.to_dict() or {}
    return {
        "collection": collection,
        "document_id": run_id,
        "exists": doc.exists,
        "run": payload,
        "project_id": client.project,
    }
