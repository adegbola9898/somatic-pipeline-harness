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
sha256_of() { sha256sum "$1" | awk '{print $1}'; }

# run_cmd "label" cmd args...
run_cmd() {
  local label="$1"; shift
  log "RUN: $label"
  log "CMD: $*"
  "$@" 1>>"$STDOUT_LOG" 2>>"$STDERR_LOG" || die "failed: $label"
}

ensure_parent() { mkdir -p "$(dirname "$1")"; }
file_nonempty() { [[ -s "$1" ]]; }

write_atomic() {
  local out="$1"
  local tmp="${out}.tmp.$$"
  ensure_parent "$out"
  cat > "$tmp"
  mv -f "$tmp" "$out"
}

sha256_of() { sha256sum "$1" | awk '{print $1}'; }

verify_sha256_sidecar_in_dir() {
  # expects sidecar in same directory; works with "sha  filename" format
  local dir="$1"
  local file="$2"
  local sidecar="$3"
  (cd "$dir" && sha256sum -c "$sidecar") >/dev/null 2>&1 \
    || die "sha256 verification failed: dir=$dir sidecar=$sidecar"
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

# Guard for flags that require a value (prevents "$2" being unset)
need_arg() {
  local flag="$1"
  shift || true
  [[ $# -ge 1 ]] || die "missing value for $flag"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sample-id) need_arg "$1" "${@:2}"; SAMPLE_ID="$2"; shift 2;;
    --fastq1) need_arg "$1" "${@:2}"; FASTQ1="$2"; shift 2;;
    --fastq2) need_arg "$1" "${@:2}"; FASTQ2="$2"; shift 2;;
    --sra) need_arg "$1" "${@:2}"; SRA="$2"; shift 2;;
    --outdir) need_arg "$1" "${@:2}"; OUTDIR="$2"; shift 2;;
    --workdir) need_arg "$1" "${@:2}"; WORKDIR="$2"; shift 2;;
    --ref-bundle-dir) need_arg "$1" "${@:2}"; REF_BUNDLE_DIR="$2"; shift 2;;
    --targets-bed) need_arg "$1" "${@:2}"; TARGETS_BED="$2"; shift 2;;
    --threads) need_arg "$1" "${@:2}"; THREADS="$2"; shift 2;;
    --enforce-qc-gate) need_arg "$1" "${@:2}"; ENFORCE_QC_GATE="$2"; shift 2;;
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

# ---- preflight inputs ----
if [[ -n "$SRA" ]]; then
  : # SRA preflight happens later (download step). For now, accept the accession string.
else
  require_file "$FASTQ1"
  require_file "$FASTQ2"
fi

require_file "$TARGETS_BED"
[[ -d "$REF_BUNDLE_DIR" ]] || die "missing reference bundle dir: $REF_BUNDLE_DIR"

# ---- derive contract paths ----
SAMPLE_ROOT="${OUTDIR%/}/${SAMPLE_ID}"
INPUTS_DIR="${SAMPLE_ROOT}/inputs"
WORK_DIR="${WORKDIR:-${SAMPLE_ROOT}/work}"
RESULTS_DIR="${SAMPLE_ROOT}/results"
QC_DIR="${SAMPLE_ROOT}/qc"
LOG_DIR="${SAMPLE_ROOT}/logs"
META_DIR="${SAMPLE_ROOT}/metadata"

step_resources() {
  local manifest="${META_DIR}/bundle_manifest_used.json"
  local contigs="${META_DIR}/contig_compatibility.tsv"

  if file_nonempty "$manifest" && file_nonempty "$contigs"; then
    log "SKIP step_resources (outputs present)"
    rm -f "${META_DIR}/ref_bundle_manifest_used.json" || true
    return
  fi

  log "RUN step_resources"

  # ---- find reference tar + sha256 sidecar in ref dir ----
  [[ -d "$REF_BUNDLE_DIR" ]] || die "ref bundle dir not found: $REF_BUNDLE_DIR"

  local ref_tar
  ref_tar="$(ls -1 "${REF_BUNDLE_DIR%/}"/*.tar.gz 2>/dev/null | head -n1 || true)"
  [[ -n "$ref_tar" ]] || die "no reference *.tar.gz found in: $REF_BUNDLE_DIR"

  local ref_tar_base
  ref_tar_base="$(basename "$ref_tar")"

  local ref_sha="${ref_tar}.sha256"
  [[ -s "$ref_sha" ]] || die "missing ref sha256 sidecar: $ref_sha"

  # Verify integrity using sidecar (must run in same dir as filename in sidecar)
  verify_sha256_sidecar_in_dir "$(dirname "$ref_tar")" "$ref_tar_base" "$(basename "$ref_sha")"

  # ---- verify targets bed + sha256 sidecar ----
  require_file "$TARGETS_BED"
  local targets_sha="${TARGETS_BED}.sha256"
  [[ -s "$targets_sha" ]] || die "missing targets bed sha256 sidecar: $targets_sha"
  verify_sha256_sidecar_in_dir "$(dirname "$TARGETS_BED")" "$(basename "$TARGETS_BED")" "$(basename "$targets_sha")"

  # ---- stage copies into inputs/refs (provenance snapshot) ----
  local refs_in="${INPUTS_DIR}/refs"
  mkdir -p "$refs_in"

  local staged_ref_tar="${refs_in}/${ref_tar_base}"
  local staged_ref_sha="${refs_in}/$(basename "$ref_sha")"
  cp -f "$ref_tar" "$staged_ref_tar"
  cp -f "$ref_sha" "$staged_ref_sha"

  local staged_targets_bed="${refs_in}/$(basename "$TARGETS_BED")"
  local staged_targets_sha="${refs_in}/$(basename "$targets_sha")"
  cp -f "$TARGETS_BED" "$staged_targets_bed"
  cp -f "$targets_sha" "$staged_targets_sha"

  # ---- unpack reference deterministically into work/refs/<bundle_id>/ ----
  local ref_bundle_id
  ref_bundle_id="$(basename "$staged_ref_tar" .tar.gz)"

  local refs_work_base="${WORK_DIR}/refs"
  local ref_work="${refs_work_base}/${ref_bundle_id}"
  mkdir -p "$refs_work_base"

  # unpack only if bundle dir not present
  if [[ ! -d "$ref_work" ]]; then
    run_cmd "untar ref bundle" tar -xzf "$staged_ref_tar" -C "$refs_work_base"
  fi

  # ---- locate FASTA + FAI ----
  local fasta
  fasta="$(ls -1 "${ref_work}"/genome/*.fa 2>/dev/null | head -n1 || true)"
  [[ -n "$fasta" ]] || die "FASTA not found under: ${ref_work}/genome/*.fa"
  local fai="${fasta}.fai"
  [[ -s "$fai" ]] || die "missing FASTA index (.fai): $fai"

  # ---- contig check: BED contigs must exist in FASTA .fai ----
  local bed_contigs="${WORK_DIR}/bed_contigs.${SAMPLE_ID}.txt"
  local fasta_contigs="${WORK_DIR}/fasta_contigs.${SAMPLE_ID}.txt"
  local missing="${WORK_DIR}/contigs_missing_in_fasta.${SAMPLE_ID}.txt"

  awk '{print $1}' "$staged_targets_bed" | grep -v '^#' | sort -u > "$bed_contigs"
  awk '{print $1}' "$fai" | sort -u > "$fasta_contigs"

  comm -23 "$bed_contigs" "$fasta_contigs" > "$missing" || true

  if [[ -s "$missing" ]]; then
    write_atomic "$contigs" <<EOF
check	status	note
bed_vs_fasta	FAIL	missing_contigs=$(wc -l < "$missing")
EOF
    log "ERROR: BED has contigs not in FASTA (.fai). Examples:"
    head -n 20 "$missing" >&2
    die "contig mismatch: BED vs FASTA"
  else
    write_atomic "$contigs" <<EOF
check	status	note
bed_vs_fasta	PASS	all_bed_contigs_in_fasta
EOF
  fi

  # ---- write manifest used ----
  local ref_tar_sha targets_bed_sha fasta_sha fai_sha
  ref_tar_sha="$(sha256_of "$staged_ref_tar")"
  targets_bed_sha="$(sha256_of "$staged_targets_bed")"
  fasta_sha="$(sha256_of "$fasta")"
  fai_sha="$(sha256_of "$fai")"

  write_atomic "$manifest" <<EOF
{
  "ref_bundle_id": "${ref_bundle_id}",
  "ref_tar": "${staged_ref_tar}",
  "ref_tar_sha256": "${ref_tar_sha}",
  "ref_root": "${ref_work}",
  "ref_fasta": "${fasta}",
  "ref_fasta_sha256": "${fasta_sha}",
  "ref_fai": "${fai}",
  "ref_fai_sha256": "${fai_sha}",
  "targets_bed": "${staged_targets_bed}",
  "targets_bed_sha256": "${targets_bed_sha}"
}
EOF

  file_nonempty "$manifest" || die "step_resources failed: missing $manifest"
  file_nonempty "$contigs" || die "step_resources failed: missing $contigs"
# Remove legacy placeholder output (kept from earlier MVP runs)
  rm -f "${META_DIR}/ref_bundle_manifest_used.json" || true
}

step_ingest() {
  local fqdir="${INPUTS_DIR}/fastq"
  local r1="${fqdir}/${SAMPLE_ID}_R1.fastq.gz"
  local r2="${fqdir}/${SAMPLE_ID}_R2.fastq.gz"
  local checksums="${META_DIR}/inputs_checksums.tsv"

  mkdir -p "$fqdir"

  # Skip if outputs already good
  if [[ -s "$r1" && -s "$r2" && -s "$checksums" ]]; then
    gzip -t "$r1" && gzip -t "$r2" && { log "SKIP step_ingest (outputs present)"; return; }
  fi

  if [[ -n "$SRA" ]]; then
    require_cmd prefetch
    require_cmd fasterq-dump
    require_cmd pigz

    # Make sra-tools deterministic inside container
    export HOME="${WORK_DIR}/.home"
    mkdir -p "$HOME"

    local sra_dir="${WORK_DIR}/sra"
    local fq_work="${WORK_DIR}/fastq_tmp"
    mkdir -p "$sra_dir" "$fq_work"

    run_cmd "prefetch" prefetch --output-directory "$sra_dir" "$SRA"

    local sra_file
    sra_file="$(find "$sra_dir" -type f -name '*.sra' | head -n 1)"
    [[ -s "$sra_file" ]] || die "prefetch produced no .sra under: $sra_dir"

    run_cmd "fasterq-dump" fasterq-dump --split-files -e "$THREADS" -O "$fq_work" "$sra_file"

    local u1 u2
    u1="$(ls -1 "$fq_work"/*_1.fastq 2>/dev/null | head -n 1)"
    u2="$(ls -1 "$fq_work"/*_2.fastq 2>/dev/null | head -n 1)"
    [[ -s "$u1" && -s "$u2" ]] || die "fasterq-dump did not produce *_1.fastq/*_2.fastq in: $fq_work"

    run_cmd "pigz R1" pigz -p "$THREADS" -c "$u1" > "$r1"
    run_cmd "pigz R2" pigz -p "$THREADS" -c "$u2" > "$r2"

  else
    require_file "$FASTQ1"
    require_file "$FASTQ2"
    gzip -t "$FASTQ1" || die "FASTQ1 failed gzip -t: $FASTQ1"
    gzip -t "$FASTQ2" || die "FASTQ2 failed gzip -t: $FASTQ2"

    ln -sf "$(readlink -f "$FASTQ1")" "$r1"
    ln -sf "$(readlink -f "$FASTQ2")" "$r2"
  fi

  require_file "$r1"
  require_file "$r2"
  gzip -t "$r1" || die "R1 failed gzip -t after ingest: $r1"
  gzip -t "$r2" || die "R2 failed gzip -t after ingest: $r2"

  {
    echo -e "type\tpath\tsha256\tsource"
    if [[ -n "$SRA" ]]; then
      echo -e "sra\t${SRA}\tNA\t${SRA}"
      echo -e "fastq1\t${r1}\t$(sha256_of "$r1")\t${SRA}"
      echo -e "fastq2\t${r2}\t$(sha256_of "$r2")\t${SRA}"
    else
      echo -e "fastq1\t${r1}\t$(sha256_of "$r1")\t${FASTQ1}"
      echo -e "fastq2\t${r2}\t$(sha256_of "$r2")\t${FASTQ2}"
    fi
  } > "$checksums"

  require_file "$checksums"
  log "RUN step_ingest"
}

step_metadata() {
  local meta="${META_DIR}/run_metadata.json"

  if file_nonempty "$meta"; then
    log "SKIP step_metadata (outputs present)"
    return
  fi

  log "RUN step_metadata"

  write_atomic "$meta" <<EOF
{
  "pipeline_version": "${PIPELINE_VERSION}",
  "sample_id": "${SAMPLE_ID}",
  "timestamp": "$(date -Is)",
  "inputs": {
    "fastq1": "${FASTQ1}",
    "fastq2": "${FASTQ2}",
    "sra": "${SRA}"
  },
  "resources": {
    "ref_bundle_dir": "${REF_BUNDLE_DIR}",
    "targets_bed": "${TARGETS_BED}"
  },
  "threads": ${THREADS},
  "enforce_qc_gate": ${ENFORCE_QC_GATE}
}
EOF

  file_nonempty "$meta" || die "step_metadata failed: missing $meta"
}

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
step_resources
step_ingest
log "TODO: step_fastp"
log "TODO: step_align"
log "TODO: step_mutect_call/filter"
log "TODO: step_qc"
step_metadata

log "DONE (skeleton)."
