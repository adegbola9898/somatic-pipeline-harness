#!/usr/bin/env bash
set -euo pipefail
umask 0022
export LC_ALL=C

##############################################
# Somatic pipeline harness (MVP skeleton)
# Contract: out/<sample>/{inputs,work,results,qc,logs,metadata}
##############################################

PIPELINE_VERSION="${PIPELINE_VERSION:-somatic-harness-v0.1}"

# ---- logging helpers (initialized after SAMPLE_ID is known) ----
log() { echo "[$(date '+%F %T')] $*" >&2; }
die() { log "ERROR: $*"; exit 2; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
require_file() { [[ -s "$1" ]] || die "missing/empty file: $1"; }

# run_cmd "label" cmd args...
run_cmd() {
  local label="$1"; shift
  log "RUN: $label"
  log "CMD: $*"
  "$@" 1>>"$STDOUT_LOG" 2>>"$STDERR_LOG" || die "failed: $label"
}

# ---- CLI (minimal; will expand next milestone item) ----
SAMPLE_ID=""
FASTQ1=""
FASTQ2=""
SRA=""
OUTDIR=""
WORKDIR=""
REF_BUNDLE_DIR=""
TARGETS_BED=""
THREADS="8"
ENFORCE_QC_GATE="0"

usage() {
  cat <<USAGE
Usage:
  run_somatic_pipeline.sh --sample-id ID --outdir DIR --ref-bundle-dir DIR --targets-bed FILE --threads N \\
    (--fastq1 FILE --fastq2 FILE | --sra SRR[,SRR...]) \\
    [--workdir DIR] [--enforce-qc-gate 0|1]

Notes:
  - Output contract: OUTDIR/ID/{inputs,work,results,qc,logs,metadata}
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sample-id) SAMPLE_ID="$2"; shift 2;;
    --fastq1) FASTQ1="$2"; shift 2;;
    --fastq2) FASTQ2="$2"; shift 2;;
    --sra) SRA="$2"; shift 2;;
    --outdir) OUTDIR="$2"; shift 2;;
    --workdir) WORKDIR="$2"; shift 2;;
    --ref-bundle-dir) REF_BUNDLE_DIR="$2"; shift 2;;
    --targets-bed) TARGETS_BED="$2"; shift 2;;
    --threads) THREADS="$2"; shift 2;;
    --enforce-qc-gate) ENFORCE_QC_GATE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: $1 (use --help)";;
  esac
done

[[ -n "$SAMPLE_ID" ]] || die "--sample-id is required"
[[ -n "$OUTDIR" ]] || die "--outdir is required"
[[ -n "$REF_BUNDLE_DIR" ]] || die "--ref-bundle-dir is required"
[[ -n "$TARGETS_BED" ]] || die "--targets-bed is required"

# exactly one input mode
if [[ -n "$SRA" ]]; then
  [[ -z "$FASTQ1" && -z "$FASTQ2" ]] || die "use either --sra OR (--fastq1,--fastq2), not both"
else
  [[ -n "$FASTQ1" && -n "$FASTQ2" ]] || die "provide --fastq1 and --fastq2 (or use --sra)"
fi

# ---- derive contract paths ----
SAMPLE_ROOT="${OUTDIR%/}/${SAMPLE_ID}"
INPUTS_DIR="${SAMPLE_ROOT}/inputs"
WORK_DIR="${WORKDIR:-${SAMPLE_ROOT}/work}"
RESULTS_DIR="${SAMPLE_ROOT}/results"
QC_DIR="${SAMPLE_ROOT}/qc"
LOG_DIR="${SAMPLE_ROOT}/logs"
META_DIR="${SAMPLE_ROOT}/metadata"

mkdir -p "$INPUTS_DIR" "$WORK_DIR" "$RESULTS_DIR" "$QC_DIR" "$LOG_DIR" "$META_DIR"

STDOUT_LOG="${LOG_DIR}/${SAMPLE_ID}.stdout.log"
STDERR_LOG="${LOG_DIR}/${SAMPLE_ID}.stderr.log"

trap 'rc=$?; [[ $rc -eq 0 ]] || log "Pipeline failed (rc=$rc). See: $STDERR_LOG"' EXIT

log "Pipeline version: $PIPELINE_VERSION"
log "Sample: $SAMPLE_ID"
log "Out: $SAMPLE_ROOT"

# ---- tool presence (minimal; will grow as steps are implemented) ----
for c in samtools bcftools gatk bwa-mem2 fastp; do require_cmd "$c"; done

# ---- placeholder steps ----
log "TODO: step_resources"
log "TODO: step_ingest"
log "TODO: step_fastp"
log "TODO: step_align"
log "TODO: step_mutect_call/filter"
log "TODO: step_qc"
log "TODO: step_metadata"

log "DONE (skeleton)."
