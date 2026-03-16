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

echo "[cloud-run-job] orchestration intent:"
echo "  1. validate runtime inputs"
echo "  2. update Firestore lifecycle state (not implemented in stub)"
echo "  3. run bin/run_somatic_pipeline.sh (not implemented in stub)"
echo "  4. run bin/upload_run_to_cloud.sh (not implemented in stub)"
echo "  5. finalize Firestore state after metadata upload (not implemented in stub)"
echo "[cloud-run-job] stub completed successfully"

exit 0
