# Somatic Pipeline Harness

A deterministic somatic variant calling pipeline for targeted panels.

The pipeline performs:

- FASTQ QC and trimming (`fastp`)
- Alignment (`bwa-mem2`)
- BAM processing (`samtools`)
- Somatic variant calling (`GATK Mutect2`)
- Variant filtering (`FilterMutectCalls`)
- Postprocessing (`bcftools`)
- Coverage QC (`bedtools`, `mosdepth`)

Outputs follow a strict contract:

OUTDIR/SAMPLE_ID/
inputs/
work/
results/
qc/
logs/
metadata/

---

# 1. Fetch reference bundle

Create required directories:

mkdir -p refs/reference refs/targets ref_cache out

Download reference bundle:

curl -L -o refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz \
https://storage.googleapis.com/somatic/somatic_refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz

curl -L -o refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz.sha256 \
https://storage.googleapis.com/somatic/somatic_refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz.sha256

Download targets BED:

curl -L -o refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed \
https://storage.googleapis.com/somatic/somatic_refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed

curl -L -o refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed.sha256 \
https://storage.googleapis.com/somatic/somatic_refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed.sha256

---

# 2. Build Docker environment

docker build -f docker/Dockerfile.dev -t somatic-dev:local .

---

# 3. Run pipeline

docker run --rm -u "$(id -u):$(id -g)" \
-v "$PWD":/work -w /work \
-v "$PWD/refs":/refs \
-v "$PWD/ref_cache":/ref_cache \
-v "$PWD/out":/out \
-e REF_CACHE_DIR=/ref_cache \
somatic-dev:local \
bash bin/run_somatic_pipeline.sh \
--sample-id DEMO1 \
--sra ERR7252107 \
--ref-bundle-dir /refs/reference \
--targets-bed /refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed \
--outdir /out \
--threads 8

---

# 4. Reference caching

On the first run the reference bundle is extracted into:

ref_cache/<bundle-id>-<sha>

Subsequent runs reuse this cache and skip extraction.
