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

ensure_ref_prereqs() {
  # usage: ensure_ref_prereqs FASTA
  # Verifies: FASTA .fai, GATK .dict, bwa-mem2 index files.
  # Prints resolved dict path to stdout.
  local fasta="$1"

  local fai="${fasta}.fai"
  [[ -s "$fai" ]] || die "missing FASTA index (.fai): $fai"

  # Accept either ref.dict (common) or ref.fa.dict (less common)
  local dict1="${fasta%.*}.dict"
  local dict2="${fasta}.dict"
  local dict=""
  if [[ -s "$dict1" ]]; then
    dict="$dict1"
  elif [[ -s "$dict2" ]]; then
    dict="$dict2"
  else
    die "missing GATK sequence dictionary (.dict) for FASTA. Expected: $dict1 (or $dict2)"
  fi

  # bwa-mem2 index files: different builds may emit slightly different bwt name variants
  local -a missing=()

  for ext in .0123 .amb .ann .pac; do
    [[ -s "${fasta}${ext}" ]] || missing+=("${fasta}${ext}")
  done

  # bwt file name differs across some bwa-mem2 builds; accept any of these
  local have_bwt=0
  for bwt in "${fasta}.bwt.2bit.64" "${fasta}.bwt.2bit.32" "${fasta}.bwt.2bit"; do
    if [[ -s "$bwt" ]]; then
      have_bwt=1
      break
    fi
  done
  if (( have_bwt == 0 )); then
    missing+=("${fasta}.bwt.2bit.64 (or .32/.bwt.2bit)")
  fi

  if (( ${#missing[@]} > 0 )); then
    die "missing bwa-mem2 index files for FASTA (run bwa-mem2 index). Missing: ${missing[*]}"
  fi

  echo "$dict"
}

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

verify_sha256_sidecar_in_dir() {
  # usage: verify_sha256_sidecar_in_dir DIR FILE SIDECAR
  local dir="$1"
  local file="$2"
  local sidecar="$3"

  require_file "${dir}/${file}"
  require_file "${dir}/${sidecar}"

  # sidecar should reference the expected file (allow " filename" or " *filename")
  grep -Eq "([[:space:]]|\\*)${file}(\r)?$" "${dir}/${sidecar}" \
    || die "sha256 sidecar does not reference expected file: dir=$dir file=$file sidecar=$sidecar"

  (cd "$dir" && sha256sum -c "$sidecar") >/dev/null 2>&1 \
    || die "sha256 verification failed: dir=$dir sidecar=$sidecar"
}

json_get_simple() {
  # usage: json_get_simple KEY FILE
  # only works for simple "key": "value" fields (your manifest format)
  local key="$1" file="$2"
  sed -n -E 's/^[[:space:]]*"'${key}'"[[:space:]]*:[[:space:]]*"([^"]*)".*$/\1/p' "$file" | head -n1
}

require_single_glob() {
  # usage: require_single_glob "desc" "/path/pattern"
  local desc="$1" pattern="$2"
  local -a matches=()
  while IFS= read -r p; do matches+=("$p"); done < <(compgen -G "$pattern" || true)

  if (( ${#matches[@]} == 0 )); then
    die "no ${desc} found (pattern: $pattern)"
  fi
  if (( ${#matches[@]} > 1 )); then
    die "multiple ${desc} found (refuse nondeterminism): ${matches[*]}"
  fi
  echo "${matches[0]}"
}

# For commands that *produce an output file via stdout* (don’t use run_cmd for these)
run_to_file() {
  # usage: run_to_file "label" OUTFILE cmd args...
  local label="$1"; local outfile="$2"; shift 2
  ensure_parent "$outfile"
  local tmp="${outfile}.tmp.$$"

  log "RUN: $label"
  log "CMD: $* > $outfile"

  # Write stdout to tmp, stderr to STDERR_LOG (atomic output)
  if ! "$@" >"$tmp" 2>>"$STDERR_LOG"; then
    rm -f "$tmp" || true
    die "failed: $label"
  fi

  [[ -s "$tmp" ]] || { rm -f "$tmp" || true; die "failed: $label (empty output)"; }
  mv -f "$tmp" "$outfile"
}

# Copy FASTQ into canonical inputs dir, but skip if already staged with same sha256.
# Refuses to overwrite if content differs (clinical-ish behavior).
stage_fastq_copy() {
  # usage: stage_fastq_copy "fastq1" SRC DEST
  local label="$1" src="$2" dst="$3"

  require_file "$src"
  gzip -t "$src" >/dev/null 2>&1 || die "${label} failed gzip -t: $src"

  ensure_parent "$dst"

  local src_abs src_sha dst_sha
  src_abs="$(readlink -f "$src")"
  src_sha="$(sha256_of "$src_abs")"

  if [[ -s "$dst" ]]; then
    gzip -t "$dst" >/dev/null 2>&1 || die "existing staged ${label} is not valid gzip: $dst"
    dst_sha="$(sha256_of "$dst")"
    if [[ "$dst_sha" == "$src_sha" ]]; then
      log "SKIP stage ${label} (sha256 match)"
      return 0
    fi
    die "existing staged ${label} differs from source (dst_sha=$dst_sha src_sha=$src_sha). Refusing to overwrite."
  fi

  local tmp="${dst}.tmp.$$"
  run_cmd "stage ${label}" cp -f "$src_abs" "$tmp"
  mv -f "$tmp" "$dst"

  gzip -t "$dst" >/dev/null 2>&1 || die "staged ${label} invalid gzip after copy: $dst"
  dst_sha="$(sha256_of "$dst")"
  [[ "$dst_sha" == "$src_sha" ]] || die "checksum mismatch after copy for ${label}"
}

# ---- output verification helpers ----
verify_vcf_gz() {
  local f="$1"
  require_file "$f"
  bcftools view -h "$f" >/dev/null 2>&1 || die "invalid VCF.gz: $f"
}

verify_targz() {
  local f="$1"
  require_file "$f"
  tar -tzf "$f" >/dev/null 2>&1 || die "invalid tar.gz: $f"
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

  # ---- find reference tar + sha256 sidecar in ref dir (deterministic) ----
  [[ -d "$REF_BUNDLE_DIR" ]] || die "ref bundle dir not found: $REF_BUNDLE_DIR"

  local ref_tar
  ref_tar="$(require_single_glob "reference *.tar.gz" "${REF_BUNDLE_DIR%/}/*.tar.gz")"

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

  # ---- parse tar sha256 from sidecar (avoid hashing huge tar) ----
  local ref_tar_sha
  ref_tar_sha="$(awk -v f="$ref_tar_base" '
    $2==f || $2=="./"f || $2=="*"f {print $1}
  ' "$ref_sha" | head -n1)"
  [[ -n "$ref_tar_sha" ]] || die "could not parse sha256 for ${ref_tar_base} from sidecar: $ref_sha"

  # ---- compute current targets sha (BED is small; OK to hash) ----
  local targets_bed_sha_cur
  targets_bed_sha_cur="$(sha256_of "$TARGETS_BED")"

  # ---- Content-aware skip: only skip if manifest matches current tar+targets ----
  if file_nonempty "$manifest" && file_nonempty "$contigs"; then
    local have_ref_sha have_targets_sha
    have_ref_sha="$(json_get_simple "ref_tar_sha256" "$manifest")"
    have_targets_sha="$(json_get_simple "targets_bed_sha256" "$manifest")"
    [[ -n "$have_ref_sha" && -n "$have_targets_sha" ]] || die "manifest missing sha fields: $manifest"

    [[ "$have_ref_sha" == "$ref_tar_sha" ]] || die \
      "existing step_resources outputs correspond to DIFFERENT ref tar sha (have=$have_ref_sha cur=$ref_tar_sha). Delete $manifest and $contigs to re-run."

    [[ "$have_targets_sha" == "$targets_bed_sha_cur" ]] || die \
      "existing step_resources outputs correspond to DIFFERENT targets bed sha (have=$have_targets_sha cur=$targets_bed_sha_cur). Delete $manifest and $contigs to re-run."

    log "SKIP step_resources (outputs present + resource shas match)"
    rm -f "${META_DIR}/ref_bundle_manifest_used.json" || true
    return
  fi

  log "RUN step_resources"

  # ---- stage provenance snapshots into inputs/refs (SMALL files only) ----
  local refs_in="${INPUTS_DIR}/refs"
  mkdir -p "$refs_in"

  # Do NOT copy the huge tar into /out. Keep using the shared mounted tar.
  local staged_ref_tar="$ref_tar"  # verified source tar path
  local staged_ref_sha="${refs_in}/$(basename "$ref_sha")"
  cp -f "$ref_sha" "$staged_ref_sha"

  local staged_targets_bed="${refs_in}/$(basename "$TARGETS_BED")"
  local staged_targets_sha="${refs_in}/$(basename "$targets_sha")"
  cp -f "$TARGETS_BED" "$staged_targets_bed"
  cp -f "$targets_sha" "$staged_targets_sha"

  # Record original source locations (human-friendly provenance)
  write_atomic "${refs_in}/ref_sources.tsv" <<EOF
type    path
ref_tar ${ref_tar}
ref_sha ${ref_sha}
targets_bed     ${TARGETS_BED}
targets_sha     ${targets_sha}
EOF

  # ---- shared unpack cache (ONE unpack total across samples) ----
  # Expect you to mount: -v /home/jupyter/ref_cache:/ref_cache
  local refs_work_base="${REF_CACHE_DIR:-/ref_cache}"
  refs_work_base="${refs_work_base%/}"
  mkdir -p "$refs_work_base" 2>/dev/null || true
  [[ -d "$refs_work_base" && -w "$refs_work_base" ]] || die \
    "ref cache not writable: $refs_work_base (mount a host dir, e.g. -v /home/jupyter/ref_cache:/ref_cache)"

  local ref_bundle_id
  ref_bundle_id="$(basename "$ref_tar" .tar.gz)"

  local sha12="${ref_tar_sha:0:12}"
  local ref_work="${refs_work_base}/${ref_bundle_id}-${sha12}"

  if [[ ! -d "$ref_work" ]]; then
    local tmp_extract="${refs_work_base}/.extract.${ref_bundle_id}.${sha12}.$$"
    mkdir -p "$tmp_extract"

    run_cmd "untar ref bundle" tar -xzf "$staged_ref_tar" -C "$tmp_extract"

    # Expect tar contains a top-level folder named ref_bundle_id
    local extracted="${tmp_extract}/${ref_bundle_id}"
    [[ -d "$extracted" ]] || die "expected ${ref_bundle_id}/ inside tar, but not found under: $tmp_extract"

    mv -f "$extracted" "$ref_work"
    rm -rf "$tmp_extract"
  fi

  # ---- locate FASTA + FAI (still minimal; deterministic if exactly one) ----
  local fasta
  fasta="$(require_single_glob "FASTA under ${ref_work}/genome" "${ref_work}/genome/*.fa")"
  # ---- prereqs: .fai + .dict + bwa-mem2 indices ----
  local dict
  dict="$(ensure_ref_prereqs "$fasta")"
  local fai="${fasta}.fai"

  # ---- contig check: BED contigs must exist in FASTA .fai ----
  local bed_contigs="${WORK_DIR}/bed_contigs.${SAMPLE_ID}.txt"
  local fasta_contigs="${WORK_DIR}/fasta_contigs.${SAMPLE_ID}.txt"
  local missing="${WORK_DIR}/contigs_missing_in_fasta.${SAMPLE_ID}.txt"

  awk '{print $1}' "$staged_targets_bed" | grep -v -E '^(#|$)' | sort -u > "$bed_contigs"
  awk '{print $1}' "$fai" | sort -u > "$fasta_contigs"

  comm -23 "$bed_contigs" "$fasta_contigs" > "$missing" || true

  if [[ -s "$missing" ]]; then
    write_atomic "$contigs" <<EOF
check   status  note
bed_vs_fasta    FAIL    missing_contigs=$(wc -l < "$missing")
EOF
    log "ERROR: BED has contigs not in FASTA (.fai). Examples:"
    head -n 20 "$missing" >&2
    die "contig mismatch: BED vs FASTA"
  else
    write_atomic "$contigs" <<EOF
check   status  note
bed_vs_fasta    PASS    all_bed_contigs_in_fasta
EOF
  fi

  # ---- write manifest used ----
  local targets_bed_sha fasta_sha fai_sha dict_sha
  targets_bed_sha="$(sha256_of "$staged_targets_bed")"
  fasta_sha="$(sha256_of "$fasta")"
  fai_sha="$(sha256_of "$fai")"
  dict_sha="$(sha256_of "$dict")"

  write_atomic "$manifest" <<EOF
{
  "ref_bundle_id": "${ref_bundle_id}",
  "ref_tar": "${ref_tar}",
  "ref_tar_sha256": "${ref_tar_sha}",
  "ref_tar_sha256_sidecar": "${staged_ref_sha}",
  "ref_cache_dir": "${refs_work_base}",
  "ref_root": "${ref_work}",
  "ref_fasta": "${fasta}",
  "ref_fasta_sha256": "${fasta_sha}",
  "ref_fai": "${fai}",
  "ref_dict": "${dict}",
  "ref_dict_sha256": "${dict_sha}",
  "bwa_mem2_prefix": "${fasta}",
  "ref_fai_sha256": "${fai_sha}",
  "targets_bed": "${staged_targets_bed}",
  "targets_bed_sha256": "${targets_bed_sha}",
  "targets_bed_sha256_sidecar": "${staged_targets_sha}"
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

  # ---- Skip ONLY if outputs are valid AND match requested inputs by CONTENT ----
  if [[ -s "$r1" && -s "$r2" && -s "$checksums" ]]; then
    gzip -t "$r1" >/dev/null 2>&1 || die "existing R1 failed gzip -t: $r1"
    gzip -t "$r2" >/dev/null 2>&1 || die "existing R2 failed gzip -t: $r2"

    # checksums must agree with staged files (protect against “valid gzip but wrong content”)
    local have1_sha have2_sha
    have1_sha="$(awk -F'\t' '$1=="fastq1"{print $3}' "$checksums" | head -n1)"
    have2_sha="$(awk -F'\t' '$1=="fastq2"{print $3}' "$checksums" | head -n1)"
    [[ -n "$have1_sha" && -n "$have2_sha" ]] || die "inputs_checksums.tsv missing fastq1/fastq2 sha256 rows: $checksums"

    [[ "$(sha256_of "$r1")" == "$have1_sha" ]] || die "existing staged R1 sha256 != recorded (delete inputs/fastq + inputs_checksums.tsv to re-run)"
    [[ "$(sha256_of "$r2")" == "$have2_sha" ]] || die "existing staged R2 sha256 != recorded (delete inputs/fastq + inputs_checksums.tsv to re-run)"

    if [[ -n "$SRA" ]]; then
      # strict field match for the SRA row
      awk -F'\t' -v sra="$SRA" '$1=="sra" && $2==sra {found=1} END{exit(found?0:1)}' "$checksums" \
        || die "existing ingest outputs were generated from a different SRA (delete inputs/fastq + inputs_checksums.tsv to re-run)"
    else
      require_file "$FASTQ1"
      require_file "$FASTQ2"

      local cur1_sha cur2_sha
      cur1_sha="$(sha256_of "$(readlink -f "$FASTQ1")")"
      cur2_sha="$(sha256_of "$(readlink -f "$FASTQ2")")"

      [[ "$have1_sha" == "$cur1_sha" && "$have2_sha" == "$cur2_sha" ]] \
        || die "existing ingest outputs were generated from different FASTQ contents (delete inputs/fastq + inputs_checksums.tsv to re-run)"
    fi

    log "SKIP step_ingest (outputs present)"
    return
  fi

  log "RUN step_ingest"

  if [[ -n "$SRA" ]]; then
    require_cmd prefetch
    require_cmd fasterq-dump
    require_cmd pigz

    export HOME="${WORK_DIR}/.home"
    mkdir -p "$HOME"

    local sra_dir="${WORK_DIR}/sra"
    local fq_work="${WORK_DIR}/fastq_tmp"
    rm -rf "$fq_work"
    mkdir -p "$sra_dir" "$fq_work"

    run_cmd "prefetch" prefetch --output-directory "$sra_dir" "$SRA"

    local sra_file=""
    if [[ -s "${sra_dir}/${SRA}/${SRA}.sra" ]]; then
      sra_file="${sra_dir}/${SRA}/${SRA}.sra"
    elif [[ -s "${sra_dir}/${SRA}.sra" ]]; then
      sra_file="${sra_dir}/${SRA}.sra"
    else
      sra_file="$(find "$sra_dir" -type f -name '*.sra' | head -n 1 || true)"
    fi
    [[ -s "$sra_file" ]] || die "prefetch produced no .sra under: $sra_dir"

    run_cmd "fasterq-dump" fasterq-dump --split-files -e "$THREADS" -O "$fq_work" "$sra_file"

    local u1 u2 u3
    u1="$(ls -1 "$fq_work"/*_1.fastq 2>/dev/null | head -n 1 || true)"
    u2="$(ls -1 "$fq_work"/*_2.fastq 2>/dev/null | head -n 1 || true)"
    u3="$(ls -1 "$fq_work"/*_3.fastq 2>/dev/null | head -n 1 || true)"
    [[ -s "$u1" && -s "$u2" ]] || die "fasterq-dump did not produce *_1.fastq/*_2.fastq in: $fq_work"

    run_to_file "pigz R1" "$r1" pigz -p "$THREADS" -c "$u1"
    run_to_file "pigz R2" "$r2" pigz -p "$THREADS" -c "$u2"

    if [[ -n "$u3" && -s "$u3" ]]; then
      log "NOTE: fasterq-dump produced unpaired *_3.fastq (deleting): $u3"
      rm -f "$u3" || true
    fi
    rm -f "$u1" "$u2" || true
    rmdir "$fq_work" 2>/dev/null || true

  else
    require_file "$FASTQ1"
    require_file "$FASTQ2"
    gzip -t "$FASTQ1" >/dev/null 2>&1 || die "FASTQ1 failed gzip -t: $FASTQ1"
    gzip -t "$FASTQ2" >/dev/null 2>&1 || die "FASTQ2 failed gzip -t: $FASTQ2"

    stage_fastq_copy "fastq1" "$FASTQ1" "$r1"
    stage_fastq_copy "fastq2" "$FASTQ2" "$r2"
  fi

  require_file "$r1"
  require_file "$r2"
  gzip -t "$r1" >/dev/null 2>&1 || die "R1 failed gzip -t after ingest: $r1"
  gzip -t "$r2" >/dev/null 2>&1 || die "R2 failed gzip -t after ingest: $r2"

  write_atomic "$checksums" <<EOF
type	path	sha256	source
$(if [[ -n "$SRA" ]]; then
    printf "sra\t%s\tNA\t%s\n" "$SRA" "$SRA"
    printf "fastq1\t%s\t%s\t%s\n" "$r1" "$(sha256_of "$r1")" "$SRA"
    printf "fastq2\t%s\t%s\t%s\n" "$r2" "$(sha256_of "$r2")" "$SRA"
  else
    printf "fastq1\t%s\t%s\t%s\n" "$r1" "$(sha256_of "$r1")" "$FASTQ1"
    printf "fastq2\t%s\t%s\t%s\n" "$r2" "$(sha256_of "$r2")" "$FASTQ2"
  fi)
EOF

  require_file "$checksums"
}

step_fastp() {
  local in_dir="${INPUTS_DIR}/fastq"
  local r1_in="${in_dir}/${SAMPLE_ID}_R1.fastq.gz"
  local r2_in="${in_dir}/${SAMPLE_ID}_R2.fastq.gz"

  local fp_work="${WORK_DIR}/fastp"
  local fp_qc="${QC_DIR}/fastp"
  mkdir -p "$fp_work" "$fp_qc"

  local r1_out="${fp_work}/${SAMPLE_ID}_R1.fastq.gz"
  local r2_out="${fp_work}/${SAMPLE_ID}_R2.fastq.gz"
  local json_out="${fp_qc}/${SAMPLE_ID}.fastp.json"
  local html_out="${fp_qc}/${SAMPLE_ID}.fastp.html"

  # Idempotent skip (basic)
  if [[ -s "$r1_out" && -s "$r2_out" && -s "$json_out" && -s "$html_out" ]]; then
    gzip -t "$r1_out" >/dev/null 2>&1 || die "existing fastp R1 output failed gzip -t: $r1_out"
    gzip -t "$r2_out" >/dev/null 2>&1 || die "existing fastp R2 output failed gzip -t: $r2_out"
    log "SKIP step_fastp (outputs present)"
    return
  fi

  log "RUN step_fastp"
  require_file "$r1_in"
  require_file "$r2_in"
  gzip -t "$r1_in" >/dev/null 2>&1 || die "input R1 failed gzip -t: $r1_in"
  gzip -t "$r2_in" >/dev/null 2>&1 || die "input R2 failed gzip -t: $r2_in"

  # Clean partial outputs to avoid mixing states
  rm -f "$r1_out" "$r2_out" "$json_out" "$html_out"

  # Minimal “v2 unchanged first” stance: no extra flags unless you already had them in v2.
  # Threading uses --thread.
  run_cmd "fastp" fastp \
    --in1 "$r1_in" --in2 "$r2_in" \
    --out1 "$r1_out" --out2 "$r2_out" \
    --json "$json_out" --html "$html_out" \
    --thread "$THREADS"

  require_file "$r1_out"
  require_file "$r2_out"
  gzip -t "$r1_out" >/dev/null 2>&1 || die "fastp R1 output failed gzip -t: $r1_out"
  gzip -t "$r2_out" >/dev/null 2>&1 || die "fastp R2 output failed gzip -t: $r2_out"
  require_file "$json_out"
  require_file "$html_out"
}

step_align() {
  require_cmd bwa-mem2
  require_cmd samtools

  mkdir -p "${RESULTS_DIR}/bam" "$QC_DIR"

  local qc_flagstat="${QC_DIR}/${SAMPLE_ID}.flagstat.txt"
  local bam="${RESULTS_DIR}/bam/${SAMPLE_ID}.sorted.markdup.bam"
  local bai="${bam}.bai"

  # pick input fastqs: prefer fastp outputs
  local r1="${WORK_DIR}/fastp/${SAMPLE_ID}_R1.fastq.gz"
  local r2="${WORK_DIR}/fastp/${SAMPLE_ID}_R2.fastq.gz"
  if [[ ! -s "$r1" || ! -s "$r2" ]]; then
    r1="${INPUTS_DIR}/fastq/${SAMPLE_ID}_R1.fastq.gz"
    r2="${INPUTS_DIR}/fastq/${SAMPLE_ID}_R2.fastq.gz"
  fi
  require_file "$r1"
  require_file "$r2"
  gzip -t "$r1" >/dev/null 2>&1 || die "R1 failed gzip -t: $r1"
  gzip -t "$r2" >/dev/null 2>&1 || die "R2 failed gzip -t: $r2"

  # read ref paths from manifest
  local manifest="${META_DIR}/bundle_manifest_used.json"
  require_file "$manifest"
  local ref_fasta
  ref_fasta="$(json_get_simple "ref_fasta" "$manifest")"
  [[ -n "$ref_fasta" ]] || die "manifest missing ref_fasta: $manifest"
  require_file "$ref_fasta"
  require_file "${ref_fasta}.fai"

  # Idempotent skip
  if [[ -s "$bam" && -s "$bai" ]]; then
    if samtools quickcheck -v "$bam" >/dev/null 2>&1; then
      log "SKIP step_align (outputs present)"
      return
    fi
    die "existing BAM failed samtools quickcheck -v: $bam (delete $bam and $bai to re-run)"
  fi

  log "RUN step_align"
  rm -f "$bam" "$bai" "$qc_flagstat"

  local tmp_pfx="${WORK_DIR}/tmp.${SAMPLE_ID}"

  run_cmd "align+markdup" env \
    THREADS="$THREADS" SID="$SAMPLE_ID" REF="$ref_fasta" R1="$r1" R2="$r2" OUTBAM="$bam" TMPPFX="$tmp_pfx" \
    bash -c '
      set -euo pipefail
      RG="$(printf "%b" "@RG\tID:${SID}\tSM:${SID}\tPL:ILLUMINA")"

      bwa-mem2 mem -t "$THREADS" -R "$RG" "$REF" "$R1" "$R2" \
      | awk '"'"'BEGIN{OFS="\t"} /^@SQ/ {hasLN=0; for(i=1;i<=NF;i++) if($i ~ /^LN:/) hasLN=1; if(!hasLN) next} {print}'"'"' \
      | samtools view -@ "$THREADS" -b - \
      | samtools sort -@ "$THREADS" -n -T "${TMPPFX}.ns" - \
      | samtools fixmate -m - - \
      | samtools sort -@ "$THREADS" -T "${TMPPFX}.cs" - \
      | samtools markdup -@ "$THREADS" - "$OUTBAM"
    '

  run_cmd "samtools index" samtools index -@ "$THREADS" "$bam" "$bai"

  # IMPORTANT: use run_to_file (run_cmd captures stdout)
  run_to_file "samtools flagstat" "$qc_flagstat" samtools flagstat -@ "$THREADS" "$bam"

  samtools quickcheck -v "$bam" >/dev/null 2>&1 || die "samtools quickcheck failed: $bam"
  require_file "$qc_flagstat"
}

step_qc_gate() {
  require_cmd samtools
  require_cmd bedtools

  local bam="${RESULTS_DIR}/bam/${SAMPLE_ID}.sorted.markdup.bam"
  local bai="${bam}.bai"
  require_file "$bam"
  require_file "$bai"
  samtools quickcheck -v "$bam" >/dev/null 2>&1 || die "samtools quickcheck failed: $bam"

  local bed="$TARGETS_BED"
  require_file "$bed"

  mkdir -p "$QC_DIR"

  local out_overall="${QC_DIR}/coverage_summary.tsv"
  local out_gene="${QC_DIR}/per_gene_coverage.tsv"
  local out_gate="${QC_DIR}/qc_gate.tsv"

  # thresholds to report (not the pass/fail thresholds)
  local thr_list="${QC_THRESHOLDS:-1,10,50,100,200,500}"

  # Idempotent skip
  if [[ -s "$out_overall" && -s "$out_gene" && -s "$out_gate" ]]; then
    log "SKIP step_qc_gate (outputs present)"
    return
  fi

  log "RUN step_qc_gate"
  rm -f "$out_overall" "$out_gene" "$out_gate"

  # ---------------------------
  # Overall coverage on targets
  # ---------------------------
  run_to_file "coverage summary (targets)" "$out_overall" bash -c "
    set -euo pipefail
    samtools depth -aa -b '$bed' '$bam' \
    | awk -v thr='$thr_list' '
      BEGIN{
        n=split(thr,t,\",\");
        for(i=1;i<=n;i++) c[i]=0;
        total=0; sum=0;
      }
      {
        d=\$3;
        total++;
        sum+=d;
        for(i=1;i<=n;i++) if(d>=t[i]) c[i]++;
      }
      END{
        if(total==0){ print \"ERROR\\tno_positions\"; exit 2 }
        print \"metric\\tvalue\";
        printf(\"target_bases\\t%d\\n\", total);
        printf(\"mean_depth\\t%.2f\\n\", sum/total);
        for(i=1;i<=n;i++){
          printf(\"pct_ge_%sx\\t%.3f\\n\", t[i], (100.0*c[i]/total));
        }
      }'
  "
  require_file "$out_overall"

  # ---------------------------
  # Per-gene coverage (bedtools)
  # ---------------------------
  local tmp_depth="${WORK_DIR}/qc.depth.${SAMPLE_ID}.bedgraph"
  rm -f "$tmp_depth"

  run_cmd "depth bedgraph (targets)" bash -c "
    set -euo pipefail
    samtools depth -aa -b '$bed' '$bam' \
      | awk 'BEGIN{OFS=\"\\t\"}{print \$1, \$2-1, \$2, \$3}' > '$tmp_depth'
  "
  require_file "$tmp_depth"

  run_cmd "per-gene coverage (bedtools)" bash -c "
    set -euo pipefail
    bedtools intersect -a '$tmp_depth' -b '$bed' -wa -wb \
      | awk -v thr='$thr_list' '
        BEGIN{ OFS=\"\\t\"; n=split(thr,T,\",\"); }
        {
          d=\$4;
          gene=\$8;   # B col4 -> field 8 with -wa -wb
          bases[gene]++; sum[gene]+=d;
          for(i=1;i<=n;i++) if(d>=T[i]) ge[gene,i]++;
        }
        END{
          print \"gene\",\"target_bases\",\"mean_depth\",\"pct_ge_1x\",\"pct_ge_10x\",\"pct_ge_50x\",\"pct_ge_100x\",\"pct_ge_200x\",\"pct_ge_500x\";
          for(g in bases){
            b=bases[g];
            mean=(b?sum[g]/b:0);
            p1=(b?100*ge[g,1]/b:0);
            p10=(b?100*ge[g,2]/b:0);
            p50=(b?100*ge[g,3]/b:0);
            p100=(b?100*ge[g,4]/b:0);
            p200=(b?100*ge[g,5]/b:0);
            p500=(b?100*ge[g,6]/b:0);
            printf \"%s\\t%d\\t%.2f\\t%.3f\\t%.3f\\t%.3f\\t%.3f\\t%.3f\\t%.3f\\n\", g,b,mean,p1,p10,p50,p100,p200,p500;
          }
        }' \
      | sort -k3,3nr > '$out_gene'
  "
  require_file "$out_gene"

  # ---------------------------
  # Gate decision (hardcoded low defaults; env override allowed)
  # ---------------------------
  local mean_depth pct100
  mean_depth="$(awk -F'\t' '$1=="mean_depth"{print $2}' "$out_overall" | head -n1)"
  pct100="$(awk -F'\t' '$1=="pct_ge_100x"{print $2}' "$out_overall" | head -n1)"
  [[ -n "$mean_depth" && -n "$pct100" ]] || die "failed to parse $out_overall"

  # Hardcoded low thresholds (baseline-safe). Override later via env if desired.
  local min_mean="${QC_MIN_MEAN_COV:-30}"
  local min_pct100="${QC_MIN_PCT_AT_100X:-10}"

  local status="PASS"
  local reason="meets_thresholds"

  awk -v v="$mean_depth" -v m="$min_mean" 'BEGIN{exit (v+0 >= m+0)?0:1}' \
    || { status="FAIL"; reason="mean_depth_below_min"; }

  if [[ "$status" == "PASS" ]]; then
    awk -v v="$pct100" -v m="$min_pct100" 'BEGIN{exit (v+0 >= m+0)?0:1}' \
      || { status="FAIL"; reason="pct_ge_100x_below_min"; }
  fi

  write_atomic "$out_gate" <<EOF
check	status	note
qc_gate	${status}	${reason}
min_mean_depth	INFO	${min_mean}
min_pct_ge_100x	INFO	${min_pct100}
mean_depth	INFO	${mean_depth}
pct_ge_100x	INFO	${pct100}
EOF
  require_file "$out_gate"

  # Enforce only if user requested AND status FAIL
  if [[ "${ENFORCE_QC_GATE:-false}" != "false" && "${ENFORCE_QC_GATE:-0}" != "0" ]]; then
    if [[ "$status" == "FAIL" ]]; then
      die "QC gate failed (${reason}); stopping before Mutect2 (set --enforce-qc-gate 0 to continue)"
    fi
  fi
}


step_mutect_call() {
  require_cmd gatk
  require_cmd bcftools
  require_cmd samtools
  require_cmd tar
  require_cmd wc

  local manifest="${META_DIR}/bundle_manifest_used.json"
  require_file "$manifest"

  local ref_fasta
  ref_fasta="$(json_get_simple "ref_fasta" "$manifest")"
  [[ -n "$ref_fasta" ]] || die "manifest missing ref_fasta: $manifest"
  require_file "$ref_fasta"

  local bam="${RESULTS_DIR}/bam/${SAMPLE_ID}.sorted.markdup.bam"
  local bai="${bam}.bai"
  require_file "$bam"
  require_file "$bai"
  samtools quickcheck -v "$bam" >/dev/null 2>&1 || die "samtools quickcheck failed: $bam"

  local out_dir="${RESULTS_DIR}/mutect2"
  mkdir -p "$out_dir"

  local vcf_raw="${out_dir}/${SAMPLE_ID}.mutect2.unfiltered.vcf.gz"
  local vcf_raw_tbi="${vcf_raw}.tbi"
  local stats_out="${out_dir}/${SAMPLE_ID}.mutect2.stats"
  local f1r2_tar="${out_dir}/${SAMPLE_ID}.mutect2.f1r2.tar.gz"

  # Idempotent skip
  if [[ -s "$vcf_raw" && -s "$vcf_raw_tbi" && -s "$stats_out" && -s "$f1r2_tar" ]]; then
    log "SKIP step_mutect_call (outputs present)"
    return 0
  fi

  # Strict partial-output refusal
  if [[ -e "$vcf_raw" || -e "$vcf_raw_tbi" || -e "$stats_out" || -e "$f1r2_tar" ]]; then
    die "partial mutect_call outputs exist; refusing overwrite. Delete:
  $vcf_raw
  $vcf_raw_tbi
  $stats_out
  $f1r2_tar
to re-run"
  fi

  log "RUN step_mutect_call"

  run_cmd "gatk Mutect2" gatk Mutect2 \
    -R "$ref_fasta" \
    -I "$bam" \
    -L "$TARGETS_BED" \
    --max-reads-per-alignment-start 0 \
    --native-pair-hmm-threads "$THREADS" \
    --f1r2-tar-gz "$f1r2_tar" \
    -O "$vcf_raw"

  verify_vcf_gz "$vcf_raw"

  run_cmd "bcftools index (raw)" bcftools index -t -f "$vcf_raw"
  require_file "$vcf_raw_tbi"

  verify_targz "$f1r2_tar"

  # Capture stats file deterministically
  local cand=""
  for c in "${vcf_raw}.stats" "${vcf_raw%.vcf.gz}.stats" "${out_dir}/${SAMPLE_ID}.mutect2.unfiltered.stats"; do
    if [[ -s "$c" ]]; then cand="$c"; break; fi
  done

  if [[ -z "$cand" ]]; then
    cand="$(ls -1 "${out_dir}"/*.stats 2>/dev/null | head -n1 || true)"
  fi

  [[ -n "$cand" && -s "$cand" ]] || die "Mutect2 stats not found after call (expected a *.stats near $vcf_raw)."

  cp -f "$cand" "$stats_out"
  require_file "$stats_out"

  local raw_n
  raw_n="$(bcftools view -H "$vcf_raw" | wc -l || true)"
  log "step_mutect_call raw_variants=$raw_n"
}

step_learn_read_orientation_model() {
  require_cmd gatk
  require_cmd tar
  require_cmd wc

  local out_dir="${RESULTS_DIR}/mutect2"
  mkdir -p "$out_dir"

  local f1r2_tar="${out_dir}/${SAMPLE_ID}.mutect2.f1r2.tar.gz"
  local rom_tar="${out_dir}/${SAMPLE_ID}.read-orientation-model.tar.gz"

  require_file "$f1r2_tar"
  verify_targz "$f1r2_tar"

  # Idempotent skip
  if [[ -s "$rom_tar" ]]; then
    log "SKIP step_learn_read_orientation_model (outputs present)"
    return 0
  fi

  # Strict partial-output refusal
  if [[ -e "$rom_tar" ]]; then
    die "partial learn_read_orientation_model outputs exist; refusing overwrite. Delete:
  $rom_tar
to re-run"
  fi

  log "RUN step_learn_read_orientation_model"

  run_cmd "gatk LearnReadOrientationModel" gatk LearnReadOrientationModel \
    -I "$f1r2_tar" \
    -O "$rom_tar"

  verify_targz "$rom_tar"

  local rom_entries
  rom_entries="$(tar -tzf "$rom_tar" | wc -l || true)"
  log "step_learn_read_orientation_model entries=$rom_entries"
}

step_mutect_filter() {
  require_cmd gatk
  require_cmd bcftools
  require_cmd wc

  local manifest="${META_DIR}/bundle_manifest_used.json"
  require_file "$manifest"

  local ref_fasta
  ref_fasta="$(json_get_simple "ref_fasta" "$manifest")"
  [[ -n "$ref_fasta" ]] || die "manifest missing ref_fasta: $manifest"
  require_file "$ref_fasta"

  local out_dir="${RESULTS_DIR}/mutect2"
  mkdir -p "$out_dir"

  local vcf_raw="${out_dir}/${SAMPLE_ID}.mutect2.unfiltered.vcf.gz"
  local vcf_raw_tbi="${vcf_raw}.tbi"
  local stats_out="${out_dir}/${SAMPLE_ID}.mutect2.stats"
  local rom_tar="${out_dir}/${SAMPLE_ID}.read-orientation-model.tar.gz"

  require_file "$vcf_raw"
  require_file "$vcf_raw_tbi"
  require_file "$stats_out"
  require_file "$rom_tar"
  verify_vcf_gz "$vcf_raw"
  verify_targz "$rom_tar"

  local vcf_filt="${out_dir}/${SAMPLE_ID}.mutect2.filtered.vcf.gz"
  local vcf_filt_tbi="${vcf_filt}.tbi"

  # Idempotent skip
  if [[ -s "$vcf_filt" && -s "$vcf_filt_tbi" ]]; then
    log "SKIP step_mutect_filter (outputs present)"
    return 0
  fi

  # Strict partial-output refusal
  if [[ -e "$vcf_filt" || -e "$vcf_filt_tbi" ]]; then
    die "partial mutect_filter outputs exist; refusing overwrite. Delete:
  $vcf_filt
  $vcf_filt_tbi
to re-run"
  fi

  log "RUN step_mutect_filter"

  run_cmd "gatk FilterMutectCalls" gatk FilterMutectCalls \
    -R "$ref_fasta" \
    -V "$vcf_raw" \
    --ob-priors "$rom_tar" \
    -O "$vcf_filt"

  verify_vcf_gz "$vcf_filt"

  run_cmd "bcftools index (filtered)" bcftools index -t -f "$vcf_filt"
  require_file "$vcf_filt_tbi"

  local total_n
  local pass_n
  total_n="$(bcftools view -H "$vcf_filt" | wc -l || true)"
  pass_n="$(bcftools view -H -f PASS "$vcf_filt" | wc -l || true)"
  log "step_mutect_filter total_variants=$total_n pass_variants=$pass_n"
}

step_postprocess_pass() {
  require_cmd bcftools
  require_cmd gzip
  require_cmd awk
  require_cmd wc

  local manifest="${META_DIR}/bundle_manifest_used.json"
  require_file "$manifest"

  local ref_fasta
  ref_fasta="$(json_get_simple "ref_fasta" "$manifest")"
  [[ -n "$ref_fasta" ]] || die "manifest missing ref_fasta: $manifest"
  require_file "$ref_fasta"
  require_file "${ref_fasta}.fai"

  local out_dir="${RESULTS_DIR}/mutect2"
  mkdir -p "$out_dir"

  # Input: filtered VCF from step_mutect_filter
  local vcf_filtered="${out_dir}/${SAMPLE_ID}.mutect2.filtered.vcf.gz"
  local vcf_filtered_tbi="${vcf_filtered}.tbi"
  require_file "$vcf_filtered"
  require_file "$vcf_filtered_tbi"

  # Outputs (ported from v2 naming)
  local pass_count_txt="${out_dir}/${SAMPLE_ID}.PASS_count.txt"
  local pass_tsv="${out_dir}/${SAMPLE_ID}.PASS_variants.tsv"
  local vcf_split="${out_dir}/${SAMPLE_ID}.PASS.norm.split.vcf.gz"
  local vcf_split_tbi="${vcf_split}.tbi"
  local vcf_split_csi="${vcf_split}.csi"
  local perallele_tsv="${out_dir}/${SAMPLE_ID}.PASS_variants.perAllele.tsv"

  # Idempotent skip: only if ALL expected outputs exist and non-empty
  # Note: bcftools index may emit .tbi OR .csi depending on contigs/length; accept either.
  if [[ -s "$pass_count_txt" && -s "$pass_tsv" && -s "$vcf_split" && ( -s "$vcf_split_tbi" || -s "$vcf_split_csi" ) && -s "$perallele_tsv" ]]; then
    log "SKIP step_postprocess_pass (outputs present)"
    return 0
  fi

  # Strict partial-output refusal (matches harness “fail-fast, don’t clobber” style)
  if [[ -e "$pass_count_txt" || -e "$pass_tsv" || -e "$vcf_split" || -e "$vcf_split_tbi" || -e "$vcf_split_csi" || -e "$perallele_tsv" ]]; then
    die "partial postprocess outputs exist; refusing overwrite. Delete:
  $pass_count_txt
  $pass_tsv
  $vcf_split
  $vcf_split_tbi
  $vcf_split_csi
  $perallele_tsv
to re-run"
  fi

  log "RUN step_postprocess_pass"

  # ---------------------------
  # PASS count
  # ---------------------------
  run_to_file "PASS count" "$pass_count_txt" bash -c "
    set -euo pipefail
    bcftools view -H -f PASS '$vcf_filtered' \
      | wc -l \
      | awk '{print \"PASS_variants\\t\" \$1}'
  "
  require_file "$pass_count_txt"

  # ---------------------------
  # PASS TSV (basic columns)
  # ---------------------------
  run_to_file "PASS TSV (basic)" "$pass_tsv" bash -c "
    set -euo pipefail
    gzip -dc '$vcf_filtered' \
    | awk 'BEGIN{FS=OFS=\"\\t\"; print \"CHROM\",\"POS\",\"ID\",\"REF\",\"ALT\",\"QUAL\",\"AF\",\"DP\"}
           /^#/ {next}
           \$7==\"PASS\" {
             split(\$9,F,\":\"); split(\$10,V,\":\");
             af=dp=\".\";
             for(i=1;i<=length(F);i++){
               if(F[i]==\"AF\") af=V[i];
               if(F[i]==\"DP\") dp=V[i];
             }
             print \$1,\$2,\$3,\$4,\$5,\$6,af,dp
           }'
  "
  require_file "$pass_tsv"

  # ---------------------------
  # PASS-only normalized + split VCF
  # ---------------------------
  run_cmd "PASS VCF split+norm" bash -c "
    set -euo pipefail
    bcftools view -f PASS '$vcf_filtered' \
      | bcftools norm -f '$ref_fasta' -m -both -Oz -o '$vcf_split'
    bcftools index -f '$vcf_split'
  "
  require_file "$vcf_split"
  if [[ -s "$vcf_split_tbi" ]]; then
    : # ok
  elif [[ -s "$vcf_split_csi" ]]; then
    : # ok
  else
    die "Missing index for split VCF (expected .tbi or .csi): $vcf_split"
  fi

  # ---------------------------
  # Per-allele TSV from split VCF
  # ---------------------------
  run_to_file "PASS per-allele TSV" "$perallele_tsv" bash -c "
    set -euo pipefail
    gzip -dc '$vcf_split' \
    | awk 'BEGIN{FS=OFS=\"\\t\"; print \"CHROM\",\"POS\",\"ID\",\"REF\",\"ALT\",\"QUAL\",\"DP\",\"AD_REF\",\"AD_ALT\",\"AF\",\"TLOD\"}
           /^#/ {next}
           {
             split(\$9,F,\":\"); split(\$10,V,\":\");
             dp=ad=af=tlod=\".\";
             for(i=1;i<=length(F);i++){
               if(F[i]==\"DP\") dp=V[i];
               if(F[i]==\"AD\") ad=V[i];
               if(F[i]==\"AF\") af=V[i];
               if(F[i]==\"TLOD\") tlod=V[i];
             }
             split(ad,a,\",\");
             ad_ref=a[1]; ad_alt=a[2];
             print \$1,\$2,\$3,\$4,\$5,\$6,dp,ad_ref,ad_alt,af,tlod
           }'
  "
  require_file "$perallele_tsv"
}

step_make_compact_pass_table() {
  require_cmd gzip
  require_cmd awk
  require_cmd wc
  require_cmd bedtools
  require_cmd sort

  local out_dir="${RESULTS_DIR}/mutect2"
  local reports_dir="${RESULTS_DIR}/reports"
  mkdir -p "$reports_dir"

  local vcf_split="${out_dir}/${SAMPLE_ID}.PASS.norm.split.vcf.gz"
  local vcf_split_tbi="${vcf_split}.tbi"
  local vcf_split_csi="${vcf_split}.csi"

  require_file "$vcf_split"
  if [[ -s "$vcf_split_tbi" ]]; then
    :
  elif [[ -s "$vcf_split_csi" ]]; then
    :
  else
    die "Missing index for split VCF (expected .tbi or .csi): $vcf_split"
  fi

  require_file "$TARGETS_BED"

  local compact_tsv="${reports_dir}/${SAMPLE_ID}.PASS.compact.tsv"
  local compact_bed_tmp="${WORK_DIR}/${SAMPLE_ID}.PASS.compact.tmp.bed"
  local compact_joined_tmp="${WORK_DIR}/${SAMPLE_ID}.PASS.compact.joined.tmp.tsv"

  # Idempotent skip
  if [[ -s "$compact_tsv" ]]; then
    log "SKIP step_make_compact_pass_table (outputs present)"
    return 0
  fi

  # Strict partial-output refusal
  if [[ -e "$compact_tsv" || -e "$compact_bed_tmp" || -e "$compact_joined_tmp" ]]; then
    die "partial compact report outputs exist; refusing overwrite. Delete:
  $compact_tsv
  $compact_bed_tmp
  $compact_joined_tmp
to re-run"
  fi

  log "RUN step_make_compact_pass_table"

  # Step 1: make a BED-like intermediate from PASS split VCF
  run_to_file "PASS compact intermediate BED" "$compact_bed_tmp" bash -c "
    set -euo pipefail
    gzip -dc '$vcf_split' \
    | awk 'BEGIN{FS=OFS=\"\t\"}
           /^#/ {next}
           {
             split(\$9,F,\":\"); split(\$10,V,\":\");
             dp=ad=af=\".\";
             for(i=1;i<=length(F);i++){
               if(F[i]==\"DP\") dp=V[i];
               if(F[i]==\"AD\") ad=V[i];
               if(F[i]==\"AF\") af=V[i];
             }

             ad_ref=\".\"; ad_alt=\".\";
             split(ad,a,\",\");
             if(a[1] != \"\") ad_ref=a[1];
             if(a[2] != \"\") ad_alt=a[2];

             tlod=\".\"; roq=\".\"; germq=\".\"; popaf=\".\";
             n=split(\$8,info,\";\");
             for(i=1;i<=n;i++){
               if(info[i] ~ /^TLOD=/){ split(info[i],x,\"=\"); tlod=x[2]; }
               else if(info[i] ~ /^ROQ=/){ split(info[i],x,\"=\"); roq=x[2]; }
               else if(info[i] ~ /^GERMQ=/){ split(info[i],x,\"=\"); germq=x[2]; }
               else if(info[i] ~ /^POPAF=/){ split(info[i],x,\"=\"); popaf=x[2]; }
             }

             # BED-like:
             # 1 chrom
             # 2 start (0-based)
             # 3 end   (1-based POS as half-open end)
             # 4 sample
             # 5 ref
             # 6 alt
             # 7 dp
             # 8 ad_ref
             # 9 ad_alt
             # 10 af
             # 11 tlod
             # 12 roq
             # 13 germq
             # 14 popaf
             print \$1,\$2-1,\$2,\"${SAMPLE_ID}\",\$4,\$5,dp,ad_ref,ad_alt,af,tlod,roq,germq,popaf
           }'
  "

  require_file "$compact_bed_tmp"

  # Step 2: intersect with gene-labelled BED and build final TSV
  run_to_file "PASS compact table" "$compact_joined_tmp" bash -c "
    set -euo pipefail
    bedtools intersect -a '$compact_bed_tmp' -b '$TARGETS_BED' -wa -wb \
    | awk 'BEGIN{FS=OFS=\"\t\"; print \"sample\",\"GENE\",\"CHROM\",\"POS\",\"REF\",\"ALT\",\"DP\",\"AD_REF\",\"AD_ALT\",\"AF\",\"TLOD\",\"ROQ\",\"GERMQ\",\"POPAF\"}
           {
             # from -a:
             sample=\$4
             chrom=\$1
             pos=\$3
             ref=\$5
             alt=\$6
             dp=\$7
             ad_ref=\$8
             ad_alt=\$9
             af=\$10
             tlod=\$11
             roq=\$12
             germq=\$13
             popaf=\$14

             # from -b: gene label is BED col4 => field 18
             gene=\$18

             print sample,gene,chrom,pos,ref,alt,dp,ad_ref,ad_alt,af,tlod,roq,germq,popaf
           }'
  "

  require_file "$compact_joined_tmp"

  # Move final output into place atomically
  mv -f "$compact_joined_tmp" "$compact_tsv"
  require_file "$compact_tsv"

  # Clean intermediate
  rm -f "$compact_bed_tmp" || true

  local n_rows
  n_rows="$(awk 'NR>1{c++} END{print c+0}' "$compact_tsv")"
  log "step_make_compact_pass_table rows=$n_rows"
}

step_annotate_pass_table() {
  require_cmd python3
  require_cmd wc

  local reports_dir="${RESULTS_DIR}/reports"
  mkdir -p "$reports_dir"

  local compact_tsv="${reports_dir}/${SAMPLE_ID}.PASS.compact.tsv"
  require_file "$compact_tsv"

  local annotated_jsonl="${reports_dir}/${SAMPLE_ID}.PASS.annotated.jsonl"
  local annotated_tsv="${reports_dir}/${SAMPLE_ID}.PASS.annotated.tsv"

  # Idempotent skip
  if [[ -s "$annotated_jsonl" && -s "$annotated_tsv" ]]; then
    log "SKIP step_annotate_pass_table (outputs present)"
    return 0
  fi

  # Strict partial-output refusal
  if [[ -e "$annotated_jsonl" || -e "$annotated_tsv" ]]; then
    die "partial annotate outputs exist; refusing overwrite. Delete:
  $annotated_jsonl
  $annotated_tsv
to re-run"
  fi

  log "RUN step_annotate_pass_table"

  python3 - "$compact_tsv" "$annotated_jsonl" "$annotated_tsv" <<'PY'
import csv
import json
import os
import sys
import time
from pathlib import Path

compact_tsv = Path(sys.argv[1])
out_jsonl = Path(sys.argv[2])
out_tsv = Path(sys.argv[3])

try:
    import requests
except Exception as e:
    raise RuntimeError("Python package 'requests' is required but not available in this runtime.") from e

if not compact_tsv.exists():
    raise FileNotFoundError(f"Missing compact TSV: {compact_tsv}")

rows = []
with compact_tsv.open() as f:
    r = csv.DictReader(f, delimiter="\t")
    required = ["CHROM", "POS", "REF", "ALT"]
    missing = [c for c in required if c not in (r.fieldnames or [])]
    if missing:
        raise ValueError(f"Compact TSV missing required columns: {missing}. Header was: {r.fieldnames}")
    for row in r:
        if not row:
            continue
        rows.append(row)

# Build per-ALT HGVS
expanded = []
for row in rows:
    chrom = row["CHROM"]
    pos = row["POS"]
    ref = row["REF"]
    alt = row["ALT"]
    alts = alt.split(",")
    for a in alts:
        hgvs = f"{chrom}:g.{pos}{ref}>{a}"
        expanded.append((hgvs, row, a))

VEP_URL = "https://rest.ensembl.org/vep/homo_sapiens/hgvs"
HEADERS = {"Content-Type": "application/json", "Accept": "application/json"}
CHUNK = 50
SLEEP_SEC = 0.2

def pick_from_transcript_consequences(tc_list):
    if not tc_list:
        return None
    for tc in tc_list:
        if tc.get("canonical") == 1 or tc.get("canonical") is True:
            return tc
    return tc_list[0]

results_by_hgvs = {}

out_jsonl.parent.mkdir(parents=True, exist_ok=True)
if out_jsonl.exists():
    out_jsonl.unlink()

n = len(expanded)
for start in range(0, n, CHUNK):
    batch = expanded[start:start+CHUNK]
    hgvs_list = [h for (h, _, _) in batch]

    payload = {"hgvs_notations": hgvs_list}
    r = requests.post(VEP_URL, headers=HEADERS, data=json.dumps(payload), timeout=120)
    if r.status_code != 200:
        raise RuntimeError(f"VEP request failed (HTTP {r.status_code}): {r.text[:500]}")

    data = r.json()
    if not isinstance(data, list):
        raise RuntimeError(f"Unexpected VEP response type: {type(data)}")

    with out_jsonl.open("a") as out:
        for item in data:
            out.write(json.dumps(item) + "\n")

            hgvs = item.get("input")
            if "error" in item:
                results_by_hgvs[hgvs] = {
                    "vep_error": item.get("error", ""),
                    "most_severe_consequence": "",
                    "gene_symbol": "",
                    "gene_id": "",
                    "transcript_id": "",
                    "hgvsc": "",
                    "hgvsp": "",
                    "protein_id": "",
                    "impact": "",
                    "sift": "",
                    "polyphen": "",
                    "clin_sig": "",
                    "existing_variation": "",
                    "gnomad_af": "",
                    "gnomad_popmax_af": "",
                }
                continue

            most = item.get("most_severe_consequence", "")
            existing = ""
            if isinstance(item.get("colocated_variants"), list) and item["colocated_variants"]:
                for cv in item["colocated_variants"]:
                    if cv.get("id"):
                        existing = cv["id"]
                        break

            tc = pick_from_transcript_consequences(item.get("transcript_consequences", [])) or {}
            gene_symbol = tc.get("gene_symbol", "") or tc.get("gene_symbol_source", "")
            gene_id = tc.get("gene_id", "")
            transcript_id = tc.get("transcript_id", "")
            hgvsc = tc.get("hgvsc", "")
            hgvsp = tc.get("hgvsp", "")
            protein_id = tc.get("protein_id", "")
            impact = tc.get("impact", "")

            sift = ""
            if tc.get("sift_prediction") is not None:
                sift = f"{tc.get('sift_prediction')}({tc.get('sift_score','')})"

            polyphen = ""
            if tc.get("polyphen_prediction") is not None:
                polyphen = f"{tc.get('polyphen_prediction')}({tc.get('polyphen_score','')})"

            clin_sig = ""
            if isinstance(item.get("colocated_variants"), list):
                for cv in item["colocated_variants"]:
                    cs = cv.get("clin_sig")
                    if cs:
                        clin_sig = ";".join(cs) if isinstance(cs, list) else str(cs)
                        break

            gnomad_af = ""
            gnomad_popmax_af = ""
            if isinstance(item.get("colocated_variants"), list):
                for cv in item["colocated_variants"]:
                    for k in ["gnomad_af", "gnomAD_AF", "gnomadg_af", "gnomad_genomes_af", "gnomade_af", "gnomad_exomes_af"]:
                        if k in cv and cv[k] is not None:
                            gnomad_af = str(cv[k])
                            break
                    for k in ["gnomad_popmax_af", "gnomAD_POPMAX_AF", "gnomad_popmax", "gnomad_genomes_popmax_af", "gnomad_exomes_popmax_af"]:
                        if k in cv and cv[k] is not None:
                            gnomad_popmax_af = str(cv[k])
                            break
                    if gnomad_af or gnomad_popmax_af:
                        break

            results_by_hgvs[hgvs] = {
                "vep_error": "",
                "most_severe_consequence": most,
                "gene_symbol": gene_symbol,
                "gene_id": gene_id,
                "transcript_id": transcript_id,
                "hgvsc": hgvsc,
                "hgvsp": hgvsp,
                "protein_id": protein_id,
                "impact": impact,
                "sift": sift,
                "polyphen": polyphen,
                "clin_sig": clin_sig,
                "existing_variation": existing,
                "gnomad_af": gnomad_af,
                "gnomad_popmax_af": gnomad_popmax_af,
            }

    time.sleep(SLEEP_SEC)

out_cols = list(rows[0].keys()) + [
    "VEP_HGVS",
    "VEP_most_severe_consequence",
    "VEP_gene_symbol",
    "VEP_gene_id",
    "VEP_transcript_id",
    "VEP_hgvsc",
    "VEP_hgvsp",
    "VEP_protein_id",
    "VEP_impact",
    "VEP_sift",
    "VEP_polyphen",
    "VEP_clin_sig",
    "VEP_existing_variation",
    "VEP_gnomad_af",
    "VEP_gnomad_popmax_af",
    "VEP_error",
]

with out_tsv.open("w", newline="") as out:
    w = csv.writer(out, delimiter="\t")
    w.writerow(out_cols)

    for hgvs, row, alt_used in expanded:
        ann = results_by_hgvs.get(hgvs, None)
        if ann is None:
            ann = {
                "vep_error": "missing_response",
                "most_severe_consequence": "",
                "gene_symbol": "",
                "gene_id": "",
                "transcript_id": "",
                "hgvsc": "",
                "hgvsp": "",
                "protein_id": "",
                "impact": "",
                "sift": "",
                "polyphen": "",
                "clin_sig": "",
                "existing_variation": "",
                "gnomad_af": "",
                "gnomad_popmax_af": "",
            }

        w.writerow(list(row.values()) + [
            hgvs,
            ann["most_severe_consequence"],
            ann["gene_symbol"],
            ann["gene_id"],
            ann["transcript_id"],
            ann["hgvsc"],
            ann["hgvsp"],
            ann["protein_id"],
            ann["impact"],
            ann["sift"],
            ann["polyphen"],
            ann["clin_sig"],
            ann["existing_variation"],
            ann["gnomad_af"],
            ann["gnomad_popmax_af"],
            ann["vep_error"],
        ])

print(f"Wrote annotated JSONL: {out_jsonl}")
print(f"Wrote annotated TSV: {out_tsv}")
print(f"Annotated rows: {len(expanded)}")
PY

  require_file "$annotated_jsonl"
  require_file "$annotated_tsv"

  local n_rows
  n_rows="$(awk 'NR>1{c++} END{print c+0}' "$annotated_tsv")"
  log "step_annotate_pass_table rows=$n_rows"
}

step_flag_variant_likelihood() {
  require_cmd python3
  require_cmd wc

  local reports_dir="${RESULTS_DIR}/reports"
  mkdir -p "$reports_dir"

  local annotated_tsv="${reports_dir}/${SAMPLE_ID}.PASS.annotated.tsv"
  require_file "$annotated_tsv"

  local flagged_tsv="${reports_dir}/${SAMPLE_ID}.PASS.flagged.tsv"
  local somaticish_tsv="${reports_dir}/${SAMPLE_ID}.PASS.somaticish.tsv"
  local germlineish_tsv="${reports_dir}/${SAMPLE_ID}.PASS.germlineish.tsv"
  local uncertain_tsv="${reports_dir}/${SAMPLE_ID}.PASS.uncertain.tsv"

  # Idempotent skip
  if [[ -s "$flagged_tsv" && -s "$somaticish_tsv" && -s "$germlineish_tsv" && -s "$uncertain_tsv" ]]; then
    log "SKIP step_flag_variant_likelihood (outputs present)"
    return 0
  fi

  # Strict partial-output refusal
  if [[ -e "$flagged_tsv" || -e "$somaticish_tsv" || -e "$germlineish_tsv" || -e "$uncertain_tsv" ]]; then
    die "partial flagging outputs exist; refusing overwrite. Delete:
  $flagged_tsv
  $somaticish_tsv
  $germlineish_tsv
  $uncertain_tsv
to re-run"
  fi

  log "RUN step_flag_variant_likelihood"

  python3 - "$annotated_tsv" "$flagged_tsv" "$somaticish_tsv" "$germlineish_tsv" "$uncertain_tsv" <<'PY'
import csv
import sys
from pathlib import Path

inp = Path(sys.argv[1])
out_flagged = Path(sys.argv[2])
out_som = Path(sys.argv[3])
out_ger = Path(sys.argv[4])
out_unc = Path(sys.argv[5])

def parse_float(x):
    try:
        return float(x)
    except Exception:
        return None

def parse_int(x):
    try:
        return int(x)
    except Exception:
        return None

def clinvar_category(raw: str) -> str:
    s = (raw or "").strip().lower()
    if not s:
        return "none"

    has_benign = ("benign" in s)
    has_path = ("pathogenic" in s)
    has_uncertain = ("uncertain" in s)

    if has_benign and not has_path and not has_uncertain:
        return "benign_like"
    if has_path and not has_benign and not has_uncertain:
        return "pathogenic_like"
    if has_uncertain and not has_benign and not has_path:
        return "uncertain"
    if has_benign or has_path or has_uncertain:
        return "conflicting"

    return "other"

rows = []
with open(inp) as f:
    r = csv.DictReader(f, delimiter="\t")
    for row in r:
        af = parse_float(row.get("AF", ""))
        dp = parse_int(row.get("DP", ""))
        ad_ref = parse_int(row.get("AD_REF", ""))
        ad_alt = parse_int(row.get("AD_ALT", ""))
        tlod = parse_float(row.get("TLOD", ""))
        roq = parse_float(row.get("ROQ", ""))
        germq = parse_float(row.get("GERMQ", ""))
        gnomad_af = parse_float(row.get("VEP_gnomad_af", ""))
        clin_sig_raw = row.get("VEP_clin_sig", "") or ""
        clin_cat = clinvar_category(clin_sig_raw)

        reasons = []
        germlineish = False
        somaticish = False

        # -----------------------------
        # Strong germline-like evidence
        # -----------------------------
        if dp is not None and af is not None and dp >= 20 and af >= 0.90:
            germlineish = True
            reasons.append("very_high_af_depth_ok")

        if ad_ref == 0 and ad_alt is not None and ad_alt >= 20:
            germlineish = True
            reasons.append("ad_ref_zero_homalt_like")

        if gnomad_af is not None and gnomad_af >= 0.001:
            germlineish = True
            reasons.append("population_af_present")

        if clin_cat == "benign_like":
            germlineish = True
            reasons.append("clinvar_benign_like")

        # -----------------------------
        # Somatic-like evidence
        # -----------------------------
        if dp is not None and af is not None and dp >= 20 and af <= 0.35:
            # only count as somatic-like if no strong germline signal
            if not germlineish:
                somaticish = True
                reasons.append("low_af_depth_ok")

        if tlod is not None and tlod >= 10:
            if somaticish:
                reasons.append("tlod_support")

        if roq is not None and roq >= 20:
            if somaticish:
                reasons.append("orientation_ok")

        # -----------------------------
        # Final classification
        # -----------------------------
        if germlineish:
            classification = "germlineish"
        elif somaticish:
            classification = "somaticish"
        else:
            classification = "uncertain"
            if not reasons:
                reasons.append("insufficient_evidence")

        row["somaticish_flag"] = "1" if classification == "somaticish" else "0"
        row["germlineish_flag"] = "1" if classification == "germlineish" else "0"
        row["classification"] = classification
        row["review_reasons"] = ";".join(reasons)
        row["clinvar_category"] = clin_cat

        rows.append(row)

fieldnames = list(rows[0].keys()) if rows else []

for path, keep_fn in [
    (out_flagged, lambda x: True),
    (out_som, lambda x: x["classification"] == "somaticish"),
    (out_ger, lambda x: x["classification"] == "germlineish"),
    (out_unc, lambda x: x["classification"] == "uncertain"),
]:
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, delimiter="\t", fieldnames=fieldnames)
        w.writeheader()
        for row in rows:
            if keep_fn(row):
                w.writerow(row)

print(f"Wrote flagged table: {out_flagged}")
print(f"Wrote somaticish table: {out_som}")
print(f"Wrote germlineish table: {out_ger}")
print(f"Wrote uncertain table: {out_unc}")
print(f"Total rows: {len(rows)}")
print(f"Somaticish rows: {sum(1 for r in rows if r['classification']=='somaticish')}")
print(f"Germlineish rows: {sum(1 for r in rows if r['classification']=='germlineish')}")
print(f"Uncertain rows: {sum(1 for r in rows if r['classification']=='uncertain')}")
PY

  require_file "$flagged_tsv"
  require_file "$somaticish_tsv"
  require_file "$germlineish_tsv"
  require_file "$uncertain_tsv"

  local n_flagged n_som n_ger n_unc
  n_flagged="$(awk 'NR>1{c++} END{print c+0}' "$flagged_tsv")"
  n_som="$(awk 'NR>1{c++} END{print c+0}' "$somaticish_tsv")"
  n_ger="$(awk 'NR>1{c++} END{print c+0}' "$germlineish_tsv")"
  n_unc="$(awk 'NR>1{c++} END{print c+0}' "$uncertain_tsv")"
  log "step_flag_variant_likelihood total=$n_flagged somaticish=$n_som germlineish=$n_ger uncertain=$n_unc"
}

step_gene_summary() {
  require_cmd python3
  require_cmd wc

  local reports_dir="${RESULTS_DIR}/reports"
  mkdir -p "$reports_dir"

  local flagged_tsv="${reports_dir}/${SAMPLE_ID}.PASS.flagged.tsv"
  local per_gene_cov="${QC_DIR}/per_gene_coverage.tsv"
  local gene_summary_tsv="${reports_dir}/${SAMPLE_ID}.gene_summary.tsv"

  require_file "$flagged_tsv"
  require_file "$per_gene_cov"

  # Idempotent skip
  if [[ -s "$gene_summary_tsv" ]]; then
    log "SKIP step_gene_summary (outputs present)"
    return 0
  fi

  # Strict partial-output refusal
  if [[ -e "$gene_summary_tsv" ]]; then
    die "partial gene summary outputs exist; refusing overwrite. Delete:
  $gene_summary_tsv
to re-run"
  fi

  log "RUN step_gene_summary"

  python3 - "$flagged_tsv" "$per_gene_cov" "$gene_summary_tsv" <<'PY'
import csv
import sys
from pathlib import Path
from statistics import mean

flagged_tsv = Path(sys.argv[1])
per_gene_cov = Path(sys.argv[2])
out_tsv = Path(sys.argv[3])

def parse_float(x):
    try:
        return float(x)
    except Exception:
        return None

# -----------------------------
# Read per-gene coverage table
# Supports either:
#   1) normal header on first row
#   2) header accidentally sorted away / absent
# -----------------------------
coverage = {}

with per_gene_cov.open() as f:
    lines = [ln.rstrip("\n") for ln in f if ln.strip()]

if not lines:
    raise RuntimeError(f"Empty per-gene coverage file: {per_gene_cov}")

first_fields = lines[0].split("\t")
has_header = first_fields[:3] == ["gene", "target_bases", "mean_depth"]

if has_header:
    r = csv.DictReader(lines, delimiter="\t")
    for row in r:
        gene = (row.get("gene", "") or "").strip()
        if not gene:
            continue
        coverage[gene] = {
            "mean_depth": row.get("mean_depth", "."),
            "pct_ge_100x": row.get("pct_ge_100x", "."),
            "target_bases": row.get("target_bases", "."),
        }
else:
    # Expected fixed column order from step_qc_gate output:
    # gene target_bases mean_depth pct_ge_1x pct_ge_10x pct_ge_50x pct_ge_100x pct_ge_200x pct_ge_500x
    for ln in lines:
        parts = ln.split("\t")
        if len(parts) < 7:
            continue
        gene = parts[0].strip()
        if not gene or gene == "gene":
            continue
        coverage[gene] = {
            "target_bases": parts[1],
            "mean_depth": parts[2],
            "pct_ge_100x": parts[6],
        }

# -----------------------------
# Read flagged variant table
# -----------------------------
genes = {}

with flagged_tsv.open() as f:
    r = csv.DictReader(f, delimiter="\t")
    for row in r:
        gene = (row.get("GENE", "") or "").strip()
        if not gene:
            gene = "NA"

        af = parse_float(row.get("AF", ""))
        tlod = parse_float(row.get("TLOD", ""))

        somaticish = row.get("somaticish_flag", "0") == "1"
        germlineish = row.get("germlineish_flag", "0") == "1"

        if gene not in genes:
            genes[gene] = {
                "pass_variant_count": 0,
                "somaticish_count": 0,
                "germlineish_count": 0,
                "afs": [],
                "tlods": [],
            }

        genes[gene]["pass_variant_count"] += 1
        if somaticish:
            genes[gene]["somaticish_count"] += 1
        if germlineish:
            genes[gene]["germlineish_count"] += 1
        if af is not None:
            genes[gene]["afs"].append(af)
        if tlod is not None:
            genes[gene]["tlods"].append(tlod)

# -----------------------------
# Ensure genes from coverage also appear
# -----------------------------
for gene in coverage:
    if gene not in genes:
        genes[gene] = {
            "pass_variant_count": 0,
            "somaticish_count": 0,
            "germlineish_count": 0,
            "afs": [],
            "tlods": [],
        }

# -----------------------------
# Write summary
# -----------------------------
with out_tsv.open("w", newline="") as out:
    w = csv.writer(out, delimiter="\t")
    w.writerow([
        "GENE",
        "pass_variant_count",
        "somaticish_count",
        "germlineish_count",
        "max_AF",
        "mean_AF",
        "max_TLOD",
        "mean_depth",
        "pct_ge_100x",
        "target_bases",
    ])

    for gene in sorted(
        genes.keys(),
        key=lambda g: (
            -genes[g]["somaticish_count"],
            -genes[g]["pass_variant_count"],
            g
        )
    ):
        afs = genes[gene]["afs"]
        tlods = genes[gene]["tlods"]

        max_af = f"{max(afs):.3f}" if afs else "."
        mean_af = f"{mean(afs):.3f}" if afs else "."
        max_tlod = f"{max(tlods):.2f}" if tlods else "."

        cov = coverage.get(gene, {})
        mean_depth = cov.get("mean_depth", ".")
        pct_ge_100x = cov.get("pct_ge_100x", ".")
        target_bases = cov.get("target_bases", ".")

        w.writerow([
            gene,
            genes[gene]["pass_variant_count"],
            genes[gene]["somaticish_count"],
            genes[gene]["germlineish_count"],
            max_af,
            mean_af,
            max_tlod,
            mean_depth,
            pct_ge_100x,
            target_bases,
        ])

print(f"Wrote gene summary: {out_tsv}")
print(f"Genes summarised: {len(genes)}")
PY

  require_file "$gene_summary_tsv"

  local n_rows
  n_rows="$(awk 'NR>1{c++} END{print c+0}' "$gene_summary_tsv")"
  log "step_gene_summary rows=$n_rows"
}

step_make_html_report() {
  require_cmd python3

  local reports_dir="${RESULTS_DIR}/reports"
  mkdir -p "$reports_dir"

  local flagged_tsv="${reports_dir}/${SAMPLE_ID}.PASS.flagged.tsv"
  local gene_summary_tsv="${reports_dir}/${SAMPLE_ID}.gene_summary.tsv"
  local html_report="${reports_dir}/${SAMPLE_ID}.report.html"
  local coverage_tsv="${QC_DIR}/coverage_summary.tsv"

  require_file "$flagged_tsv"
  require_file "$gene_summary_tsv"
  require_file "$coverage_tsv"

  local uncertain_tsv="${reports_dir}/${SAMPLE_ID}.PASS.uncertain.tsv"
  local run_meta="${META_DIR}/run_metadata.json"

  # Idempotent skip
  if [[ -s "$html_report" ]]; then
    log "SKIP step_make_html_report (outputs present)"
    return 0
  fi

  # Strict partial-output refusal
  if [[ -e "$html_report" ]]; then
    die "partial html report outputs exist; refusing overwrite. Delete:
  $html_report
to re-run"
  fi

  log "RUN step_make_html_report"

  python3 - "$flagged_tsv" "$gene_summary_tsv" "$coverage_tsv" "$html_report" "$run_meta" "$uncertain_tsv" "$SAMPLE_ID" "$PIPELINE_VERSION" "$SRA" <<'PY'
import csv
import html
import json
import sys
from pathlib import Path

flagged_tsv = Path(sys.argv[1])
gene_summary_tsv = Path(sys.argv[2])
coverage_tsv = Path(sys.argv[3])
html_report = Path(sys.argv[4])
run_meta = Path(sys.argv[5])
uncertain_tsv = Path(sys.argv[6])
sample_id = sys.argv[7]
pipeline_version = sys.argv[8]
sra_id = sys.argv[9]

def read_tsv(path):
    with path.open() as f:
        return list(csv.DictReader(f, delimiter="\t"))

def read_coverage(path):
    metrics = {}
    with path.open() as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) != 2:
                continue
            if parts[0] == "metric":
                continue
            metrics[parts[0]] = parts[1]
    return metrics

def html_table(rows, columns, max_rows=None):
    if max_rows is not None:
        rows = rows[:max_rows]

    out = []
    out.append('<table>')
    out.append('<thead><tr>')
    for c in columns:
        out.append(f'<th>{html.escape(c)}</th>')
    out.append('</tr></thead>')
    out.append('<tbody>')

    if not rows:
        out.append(f'<tr><td colspan="{len(columns)}">No rows</td></tr>')
    else:
        for row in rows:
            out.append('<tr>')
            for c in columns:
                val = row.get(c, "")
                out.append(f'<td>{html.escape(str(val))}</td>')
            out.append('</tr>')

    out.append('</tbody></table>')
    return "\n".join(out)

flagged_rows = read_tsv(flagged_tsv)
gene_rows = read_tsv(gene_summary_tsv)
coverage = read_coverage(coverage_tsv)

uncertain_count = 0
if uncertain_tsv.exists():
    uncertain_rows = read_tsv(uncertain_tsv)
    uncertain_count = len(uncertain_rows)

somaticish_count = sum(1 for r in flagged_rows if r.get("classification") == "somaticish")
germlineish_count = sum(1 for r in flagged_rows if r.get("classification") == "germlineish")
pass_count = len(flagged_rows)
gene_count = len(gene_rows)

top_gene_rows = gene_rows[:15]

top_variant_rows = sorted(
    flagged_rows,
    key=lambda r: (
        {"somaticish": 0, "uncertain": 1, "germlineish": 2}.get(r.get("classification", "uncertain"), 9),
        -float(r.get("TLOD", "0") or 0),
        -float(r.get("AF", "0") or 0),
    )
)[:25]

meta_timestamp = ""
if run_meta.exists():
    try:
        meta = json.loads(run_meta.read_text())
        meta_timestamp = meta.get("timestamp", "")
    except Exception:
        meta_timestamp = ""

css = """
body {
  font-family: Arial, sans-serif;
  margin: 24px;
  color: #222;
  line-height: 1.4;
}
h1, h2 {
  margin-bottom: 0.4rem;
}
.summary-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 12px;
  margin-bottom: 24px;
}
.card {
  border: 1px solid #ddd;
  border-radius: 10px;
  padding: 12px;
  background: #fafafa;
}
.card .label {
  font-size: 0.9rem;
  color: #666;
}
.card .value {
  font-size: 1.3rem;
  font-weight: bold;
  margin-top: 4px;
}
table {
  border-collapse: collapse;
  width: 100%;
  margin-bottom: 24px;
  font-size: 0.95rem;
}
th, td {
  border: 1px solid #ddd;
  padding: 8px;
  text-align: left;
  vertical-align: top;
}
th {
  background: #f0f0f0;
}
.muted {
  color: #666;
}
.section {
  margin-top: 28px;
}
"""

html_parts = []
html_parts.append("<!DOCTYPE html>")
html_parts.append("<html><head><meta charset='utf-8'>")
html_parts.append(f"<title>{html.escape(sample_id)} report</title>")
html_parts.append(f"<style>{css}</style>")
html_parts.append("</head><body>")

html_parts.append(f"<h1>Somatic Pipeline Report: {html.escape(sample_id)}</h1>")
html_parts.append("<p class='muted'>")
html_parts.append(f"Pipeline version: {html.escape(pipeline_version)}")
if sra_id:
    html_parts.append(f" | SRA: {html.escape(sra_id)}")
if meta_timestamp:
    html_parts.append(f" | Run timestamp: {html.escape(meta_timestamp)}")
html_parts.append("</p>")

html_parts.append("<div class='summary-grid'>")
for label, value in [
    ("PASS variants", pass_count),
    ("Somaticish variants", somaticish_count),
    ("Germlineish variants", germlineish_count),
    ("Uncertain variants", uncertain_count),
    ("Genes summarised", gene_count),
    ("Mean depth", coverage.get("mean_depth", ".")),
    ("% >= 100x", coverage.get("pct_ge_100x", ".")),
]:
    html_parts.append("<div class='card'>")
    html_parts.append(f"<div class='label'>{html.escape(str(label))}</div>")
    html_parts.append(f"<div class='value'>{html.escape(str(value))}</div>")
    html_parts.append("</div>")
html_parts.append("</div>")

html_parts.append("<div class='section'>")
html_parts.append("<h2>Coverage Summary</h2>")
coverage_rows = [
    {"metric": "target_bases", "value": coverage.get("target_bases", ".")},
    {"metric": "mean_depth", "value": coverage.get("mean_depth", ".")},
    {"metric": "pct_ge_10x", "value": coverage.get("pct_ge_10x", ".")},
    {"metric": "pct_ge_50x", "value": coverage.get("pct_ge_50x", ".")},
    {"metric": "pct_ge_100x", "value": coverage.get("pct_ge_100x", ".")},
    {"metric": "pct_ge_200x", "value": coverage.get("pct_ge_200x", ".")},
]
html_parts.append(html_table(coverage_rows, ["metric", "value"]))
html_parts.append("</div>")

html_parts.append("<div class='section'>")
html_parts.append("<h2>Top Genes</h2>")
html_parts.append(html_table(
    top_gene_rows,
    ["GENE", "pass_variant_count", "somaticish_count", "germlineish_count", "max_AF", "mean_AF", "max_TLOD", "mean_depth", "pct_ge_100x"],
    max_rows=15
))
html_parts.append("</div>")

html_parts.append("<div class='section'>")
html_parts.append("<h2>Top Variants</h2>")
html_parts.append(html_table(
    top_variant_rows,
    ["GENE", "CHROM", "POS", "REF", "ALT", "AF", "TLOD", "classification", "review_reasons", "VEP_most_severe_consequence", "VEP_gene_symbol", "VEP_clin_sig"],
    max_rows=25
))
html_parts.append("</div>")

html_parts.append("</body></html>")

html_report.write_text("\n".join(html_parts), encoding="utf-8")
print(f"Wrote HTML report: {html_report}")
PY

  require_file "$html_report"
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
step_fastp
step_align
step_qc_gate
step_mutect_call
step_learn_read_orientation_model
step_mutect_filter
step_postprocess_pass
step_make_compact_pass_table
step_annotate_pass_table
step_flag_variant_likelihood
step_gene_summary
step_make_html_report

step_metadata

log "DONE (skeleton)."
