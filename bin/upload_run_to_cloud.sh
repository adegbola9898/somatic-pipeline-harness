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

RUN_ROOT="runs/${RUN_ID}"
DEST="gs://${BUCKET}/runs/${RUN_ID}"

echo "Preparing upload"
echo "Run ID: ${RUN_ID}"
echo "Run root: ${RUN_ROOT}"
echo "Destination: ${DEST}"

if [[ ! -d "${RUN_ROOT}" ]]; then
  echo "ERROR: run root does not exist: ${RUN_ROOT}"
  exit 1
fi

echo "Uploader stub ready."
echo "No files uploaded yet."
