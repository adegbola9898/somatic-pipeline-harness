#!/usr/bin/env bash
set -euo pipefail

required_env_vars=(
  RUN_ID
  RUNS_BUCKET
  FIRESTORE_COLLECTION
  GOOGLE_CLOUD_PROJECT
  INPUT_MODE
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

THREADS="${THREADS:-4}"
TARGETS_BED="${TARGETS_BED:-/refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed}"

resolve_fastq_path() {
  local input_path="$1"
  local uploads_prefix="gs://${UPLOADS_BUCKET}/"

  if [[ "${input_path}" == ${uploads_prefix}* ]]; then
    local rel_path="${input_path#${uploads_prefix}}"
    echo "/uploads/${rel_path}"
    return 0
  fi

  echo "${input_path}"
}

echo "[cloud-run-job] starting stub entrypoint"
echo "[cloud-run-job] RUN_ID=${RUN_ID}"
echo "[cloud-run-job] RUNS_BUCKET=${RUNS_BUCKET}"
echo "[cloud-run-job] UPLOADS_BUCKET=${UPLOADS_BUCKET:-}"
echo "[cloud-run-job] FIRESTORE_COLLECTION=${FIRESTORE_COLLECTION}"
echo "[cloud-run-job] GOOGLE_CLOUD_PROJECT=${GOOGLE_CLOUD_PROJECT}"
echo "[cloud-run-job] INPUT_MODE=${INPUT_MODE}"
echo "[cloud-run-job] THREADS=${THREADS}"
echo "[cloud-run-job] TARGETS_BED=${TARGETS_BED}"

case "${INPUT_MODE}" in
  sra)
    if [[ -z "${SRA:-}" ]]; then
      echo "[cloud-run-job] SRA is required when INPUT_MODE=sra" >&2
      exit 1
    fi
    echo "[cloud-run-job] SRA=${SRA}"
    ;;
  fastq_pair)
    if [[ -z "${FASTQ1:-}" || -z "${FASTQ2:-}" ]]; then
      echo "[cloud-run-job] FASTQ1 and FASTQ2 are required when INPUT_MODE=fastq_pair" >&2
      exit 1
    fi
    echo "[cloud-run-job] FASTQ1=${FASTQ1}"
    echo "[cloud-run-job] FASTQ2=${FASTQ2}"
    ;;
  *)
    echo "[cloud-run-job] unsupported INPUT_MODE=${INPUT_MODE}" >&2
    exit 1
    ;;
esac

FAILED_STEP="entrypoint"
FAILURE_CATEGORY="entrypoint_validation"

on_error() {
  local exit_code="$?"
  echo "[cloud-run-job] failed with exit_code=${exit_code}" >&2
  firestore_update_status "failed" false "${FAILED_STEP}" "${exit_code}" "${FAILURE_CATEGORY}" "${FAILED_STEP}" || true
  exit "${exit_code}"
}

trap on_error ERR

firestore_update_status() {
  local status="$1"
  local metadata_finalized="$2"
  local failed_step="${3:-}"
  local exit_code="${4:-}"
  local failure_category="${5:-}"
  local failure_reason="${6:-}"

  local cmd=(
    python3 bin/firestore_update.py
    --project "${GOOGLE_CLOUD_PROJECT}"
    --collection "${FIRESTORE_COLLECTION}"
    --run-id "${RUN_ID}"
    --status "${status}"
    --metadata-finalized "${metadata_finalized}"
  )

  if [[ -n "${failed_step}" ]]; then
    cmd+=(--failed-step "${failed_step}")
  fi

  if [[ -n "${exit_code}" ]]; then
    cmd+=(--exit-code "${exit_code}")
  fi

  if [[ -n "${failure_category}" ]]; then
    cmd+=(--failure-category "${failure_category}")
  fi

  if [[ -n "${failure_reason}" ]]; then
    cmd+=(--failure-reason "${failure_reason}")
  fi

  "${cmd[@]}"
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

FAILED_STEP="pipeline"
FAILURE_CATEGORY="pipeline_failure"

if [[ "${INPUT_MODE}" == "sra" ]]; then
  bin/run_somatic_pipeline.sh \
    --sample-id "${RUN_ID}" \
    --outdir "${OUTDIR}" \
    --ref-bundle-dir /refs/reference \
    --targets-bed "${TARGETS_BED}" \
    --sra "${SRA}" \
    --threads "${THREADS}" \
    --enforce-qc-gate 1
elif [[ "${INPUT_MODE}" == "fastq_pair" ]]; then
  RESOLVED_FASTQ1="$(resolve_fastq_path "${FASTQ1}")"
  RESOLVED_FASTQ2="$(resolve_fastq_path "${FASTQ2}")"
  echo "[cloud-run-job] RESOLVED_FASTQ1=${RESOLVED_FASTQ1}"
  echo "[cloud-run-job] RESOLVED_FASTQ2=${RESOLVED_FASTQ2}"

  bin/run_somatic_pipeline.sh \
    --sample-id "${RUN_ID}" \
    --outdir "${OUTDIR}" \
    --ref-bundle-dir /refs/reference \
    --targets-bed "${TARGETS_BED}" \
    --fastq1 "${RESOLVED_FASTQ1}" \
    --fastq2 "${RESOLVED_FASTQ2}" \
    --threads "${THREADS}" \
    --enforce-qc-gate 1
fi

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

