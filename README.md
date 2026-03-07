## Somatic Pipeline Harness

A deterministic somatic variant calling pipeline for targeted sequencing panels.

The pipeline is containerised with Docker and designed to be:

reproducible

idempotent

cache-aware

portable across machines

The goal of this project is to provide a clean, deterministic harness for targeted somatic variant analysis with strong reproducibility guarantees.

## Workflow Overview

The pipeline performs the following steps:

FASTQ ingestion

Download sequencing data from SRA

Convert to FASTQ

Read QC and trimming

fastp

Alignment

bwa-mem2

BAM processing

samtools sort

samtools fixmate

samtools markdup

samtools index

Coverage QC

samtools depth

bedtools

Somatic variant calling

GATK Mutect2

Orientation bias modeling

GATK LearnReadOrientationModel

Variant filtering

GATK FilterMutectCalls

Variant post-processing

bcftools norm

PASS variant extraction

per-allele TSV generation

## Pipeline Output Structure

Outputs follow a strict contract:

OUTDIR/SAMPLE_ID/
    inputs/
    work/
    results/
    qc/
    logs/
    metadata/

Example:

out/DEMO1/
    inputs/
    logs/
    metadata/
    qc/
    results/
    work/
## Important Outputs
BAM
results/bam/
    SAMPLE.sorted.markdup.bam
    SAMPLE.sorted.markdup.bam.bai
# Mutect2 Outputs
results/mutect2/

    SAMPLE.mutect2.unfiltered.vcf.gz
    SAMPLE.mutect2.unfiltered.vcf.gz.tbi

    SAMPLE.mutect2.filtered.vcf.gz
    SAMPLE.mutect2.filtered.vcf.gz.tbi

    SAMPLE.mutect2.stats

    SAMPLE.mutect2.f1r2.tar.gz
    SAMPLE.read-orientation-model.tar.gz

These files correspond to the Mutect2 orientation bias workflow:

Mutect2
→ LearnReadOrientationModel
→ FilterMutectCalls (--ob-priors)
# PASS Variant Outputs
results/mutect2/

    SAMPLE.PASS.norm.split.vcf.gz
    SAMPLE.PASS.norm.split.vcf.gz.csi

    SAMPLE.PASS_variants.tsv
    SAMPLE.PASS_variants.perAllele.tsv

    SAMPLE.PASS_count.txt

These files represent high-confidence PASS variants after filtering.

# QC Outputs
qc/

    coverage_summary.tsv
    per_gene_coverage.tsv
    SAMPLE.flagstat.txt

These files summarise:

mean coverage

percentage of bases above coverage thresholds

per-gene coverage statistics

alignment statistics

## Fetch Reference Bundle

Create required directories:

mkdir -p refs/reference refs/targets ref_cache out

Download the reference bundle:

curl -L -o refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz \
https://storage.googleapis.com/somatic/somatic_refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz

Checksum:

curl -L -o refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz.sha256 \
https://storage.googleapis.com/somatic/somatic_refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz.sha256

Download the target panel:

curl -L -o refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed \
https://storage.googleapis.com/somatic/somatic_refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed

Checksum:

curl -L -o refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed.sha256 \
https://storage.googleapis.com/somatic/somatic_refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed.sha256

If the download is interrupted (large file), resume with:

curl -L -C - -o refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz
## Build Docker Environment
docker build -f docker/Dockerfile.dev -t somatic-dev:local .
## Run the Pipeline

Example run:

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
## Reference Caching

On the first run the reference bundle is extracted into:

ref_cache/

Subsequent runs reuse this cache and skip extraction.

Example log:

SKIP step_resources (outputs present + resource shas match)
## Idempotent Pipeline Execution

The pipeline automatically skips completed steps.

Example warm run output:

SKIP step_resources
SKIP step_ingest
SKIP step_fastp
SKIP step_align
SKIP step_qc_gate
SKIP step_mutect_call
SKIP step_learn_read_orientation_model
SKIP step_mutect_filter
SKIP step_postprocess_pass

This allows rapid re-execution without recomputing completed stages.

## Reproducibility Test

Tested on a fresh Ubuntu WSL environment.

Cold run:

real 38m23s

Warm run (no recomputation):

real 56s

This demonstrates:

deterministic outputs

reference caching

idempotent execution

## WSL Memory Configuration

If running under WSL2, increase memory allocation to prevent bwa-mem2 from being killed by the OOM killer.

Create:

%USERPROFILE%\.wslconfig

Example configuration:

[wsl2]
memory=28GB
processors=8
swap=8GB

Restart WSL:

wsl --shutdown
## Notes

For machines with limited RAM, reduce threads:

--threads 2

Alignment and sorting are the most memory-intensive steps.

## What This Pipeline Guarantees

deterministic execution

containerised environment

reference integrity verification

cache-aware execution

structured output contract

reproducible somatic variant calling workflow
