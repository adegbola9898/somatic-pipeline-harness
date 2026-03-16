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

EXECUTE=false

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <run_id> <bucket> [--execute]"
  exit 1
fi

RUN_ID="$1"
BUCKET="$2"

if [[ $# -eq 3 ]]; then
  if [[ "$3" == "--execute" ]]; then
    EXECUTE=true
  else
    echo "ERROR: unknown option: $3"
    exit 1
  fi
fi

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

declare -a UPLOAD_PLAN=()

add_file_to_plan() {
  local src="$1"
  local dst="$2"

  if [[ -f "${src}" ]]; then
    UPLOAD_PLAN+=("${src}|${dst}")
  fi
}

add_dir_files_to_plan() {
  local src_dir="$1"
  local dst_prefix="$2"

  if [[ ! -d "${src_dir}" ]]; then
    return 0
  fi

  while IFS= read -r -d '' path; do
    local rel
    rel="${path#${src_dir}/}"
    UPLOAD_PLAN+=("${path}|${dst_prefix}/${rel}")
  done < <(find "${src_dir}" -maxdepth 1 -type f -print0 | sort -z)
}

echo "Building dry-run upload plan..."

# metadata
add_file_to_plan "${METADATA_DIR}/run_manifest.json" "${DEST}/metadata/run_manifest.json"
add_file_to_plan "${METADATA_DIR}/status.json" "${DEST}/metadata/status.json"
add_file_to_plan "${METADATA_DIR}/artifacts.json" "${DEST}/metadata/artifacts.json"

# logs
add_file_to_plan "${LOGS_DIR}/${SAMPLE_ID}.stdout.log" "${DEST}/logs/${SAMPLE_ID}.stdout.log"
add_file_to_plan "${LOGS_DIR}/${SAMPLE_ID}.stderr.log" "${DEST}/logs/${SAMPLE_ID}.stderr.log"

# qc
add_dir_files_to_plan "${RUN_ROOT}/qc" "${DEST}/qc"

# reports
add_dir_files_to_plan "${RUN_ROOT}/results/reports" "${DEST}/reports"

# bam
add_dir_files_to_plan "${RUN_ROOT}/results/bam" "${DEST}/outputs/bam"

# mutect2
add_dir_files_to_plan "${RUN_ROOT}/results/mutect2" "${DEST}/outputs/mutect2"

echo "Dry-run upload plan:"
for entry in "${UPLOAD_PLAN[@]}"; do
  src="${entry%%|*}"
  dst="${entry#*|}"
  echo "  ${src} -> ${dst}"
done

echo "Planned file count: ${#UPLOAD_PLAN[@]}"

if [[ "${EXECUTE}" == "false" ]]; then
  echo "Dry-run mode (no uploads performed)."
  echo "Use --execute to perform the upload."
  exit 0
fi

echo "Executing upload..."

for entry in "${UPLOAD_PLAN[@]}"; do
  src="${entry%%|*}"
  dst="${entry#*|}"

  echo "Uploading: ${src}"
  gsutil cp "${src}" "${dst}"
done

echo "Upload complete."
