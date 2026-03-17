#!/usr/bin/env bash
set -euo pipefail

required_env_vars=(
  RUN_ID
  RUNS_BUCKET
)

missing=()

for var_name in "${required_env_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    missing+=("${var_name}")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "[cloud-run-job] missing required environment variables:" >&2
  for var_name in "${missing[@]}"; do
    echo "  - ${var_name}" >&2
  done
  exit 1
fi

echo "[cloud-run-job] starting stub entrypoint"
echo "[cloud-run-job] RUN_ID=${RUN_ID}"
echo "[cloud-run-job] RUNS_BUCKET=${RUNS_BUCKET}"

on_error() {
  local exit_code="$?"
  echo "[cloud-run-job] failed with exit_code=${exit_code}" >&2
  firestore_update_status "failed" false || true
  exit "${exit_code}"
}

trap on_error ERR

firestore_update_status() {
  local status="$1"
  local metadata_finalized="$2"
  local metadata_finalized_py="False"

  if [[ "${metadata_finalized}" == "true" ]]; then
    metadata_finalized_py="True"
  fi

  python3 - <<PY_FIRESTORE
from datetime import datetime, timezone
from google.cloud import firestore

client = firestore.Client(project="${GOOGLE_CLOUD_PROJECT}")
doc = client.collection("${FIRESTORE_COLLECTION}").document("${RUN_ID}")
doc.set(
    {
        "status": "${status}",
        "metadata_finalized": ${metadata_finalized_py},
        "updated_at": datetime.now(timezone.utc).isoformat(),
    },
    merge=True,
)
print("firestore_status_updated", "${status}")
PY_FIRESTORE
}

if [[ -n "${PIPELINE_WORKDIR:-}" ]]; then
  echo "[cloud-run-job] PIPELINE_WORKDIR=${PIPELINE_WORKDIR}"
else
  echo "[cloud-run-job] PIPELINE_WORKDIR not set"
fi

if [[ -n "${PIPELINE_CONFIG:-}" ]]; then
  echo "[cloud-run-job] PIPELINE_CONFIG=${PIPELINE_CONFIG}"
else
  echo "[cloud-run-job] PIPELINE_CONFIG not set"
fi

OUTDIR="${PIPELINE_OUTDIR:-/tmp/pipeline_out}"
mkdir -p "${OUTDIR}"
echo "[cloud-run-job] PIPELINE_OUTDIR=${OUTDIR}"

firestore_update_status "running" false

echo "[cloud-run-job] running pipeline"

bin/run_somatic_pipeline.sh \
  --sample-id "${RUN_ID}" \
  --outdir "${OUTDIR}" \
  --ref-bundle-dir /refs/reference \
  --targets-bed /refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed \
  --sra ERR7252107 \
  --threads 4 \
  --enforce-qc-gate 1

echo "[cloud-run-job] storage auth probe"

python3 - <<PY_STORAGE
from google.cloud import storage

client = storage.Client(project="${GOOGLE_CLOUD_PROJECT}")
bucket = client.bucket("${RUNS_BUCKET}")
blobs = list(client.list_blobs(bucket, prefix="runs/", max_results=1))
print("storage_probe_ok", len(blobs))
PY_STORAGE

echo "[cloud-run-job] uploading results"
bin/upload_run_to_cloud.sh "${RUN_ID}" "${RUNS_BUCKET}" --execute

firestore_update_status "succeeded" true

