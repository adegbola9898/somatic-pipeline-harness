#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# upload_run_to_cloud.sh
#
# Upload a completed pipeline run to cloud storage according
# to the Module 4 storage contract.
#
# Spec references:
#   docs/storage/upload_contract.md
#   docs/storage/uploader_behavior.md
# ------------------------------------------------------------

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <run_id> <bucket>"
  exit 1
fi

RUN_ID="$1"
BUCKET="$2"

RUN_ROOT_CANDIDATES=(
  "runs/${RUN_ID}"
  "out/runs/${RUN_ID}"
)

RUN_ROOT=""
for candidate in "${RUN_ROOT_CANDIDATES[@]}"; do
  if [[ -d "${candidate}" ]]; then
    RUN_ROOT="${candidate}"
    break
  fi
done

DEST="gs://${BUCKET}/runs/${RUN_ID}"

if [[ -z "${RUN_ROOT}" ]]; then
  echo "ERROR: run root not found for run_id=${RUN_ID}"
  echo "Checked:"
  for candidate in "${RUN_ROOT_CANDIDATES[@]}"; do
    echo "  - ${candidate}"
  done
  exit 1
fi

METADATA_DIR="${RUN_ROOT}/metadata"
LOGS_DIR="${RUN_ROOT}/logs"

REQUIRED_METADATA_FILES=(
  "${METADATA_DIR}/run_manifest.json"
  "${METADATA_DIR}/status.json"
  "${METADATA_DIR}/artifacts.json"
)

echo "Preparing upload"
echo "Run ID: ${RUN_ID}"
echo "Run root: ${RUN_ROOT}"
echo "Destination: ${DEST}"

echo "Validating required metadata files..."
for path in "${REQUIRED_METADATA_FILES[@]}"; do
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required metadata file missing: ${path}"
    exit 1
  fi
done
echo "Required metadata files present."

SAMPLE_ID="$(python3 - <<'PY' "${METADATA_DIR}/run_manifest.json"
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

sample_id = data.get("sample_id")
if not sample_id:
    raise SystemExit("ERROR: sample_id missing from run_manifest.json")

print(sample_id)
PY
)"

REQUIRED_LOG_FILES=(
  "${LOGS_DIR}/${SAMPLE_ID}.stdout.log"
  "${LOGS_DIR}/${SAMPLE_ID}.stderr.log"
)

echo "Resolved sample ID: ${SAMPLE_ID}"
echo "Validating required log files..."
for path in "${REQUIRED_LOG_FILES[@]}"; do
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required log file missing: ${path}"
    exit 1
  fi
done
echo "Required log files present."

echo "Uploader stub ready."
echo "No files uploaded yet."
