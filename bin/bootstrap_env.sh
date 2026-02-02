#!/usr/bin/env bash
set -euo pipefail
umask 0022

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_YML="${ROOT}/env/environment.yml"

: "${ENV_DIR:=${HOME}/envs/genomics}"
: "${BIN_DIR:=${HOME}/bin}"
MM="${BIN_DIR}/micromamba"

mkdir -p "$BIN_DIR" "$(dirname "$ENV_DIR")"

if [[ ! -x "$MM" ]]; then
  echo "[bootstrap] Installing micromamba -> $MM"
  curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest \
    | tar -xvj -C "$BIN_DIR" --strip-components=1 bin/micromamba
fi

echo "[bootstrap] Creating/updating env at: $ENV_DIR"
"$MM" create -y -p "$ENV_DIR" -f "$ENV_YML"

echo "[bootstrap] Done."
"$MM" run -p "$ENV_DIR" samtools --version | head -n 1
"$MM" run -p "$ENV_DIR" bcftools --version | head -n 2
"$MM" run -p "$ENV_DIR" gatk --version
