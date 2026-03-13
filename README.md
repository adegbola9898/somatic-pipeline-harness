# Somatic Pipeline Harness

A deterministic somatic variant calling pipeline for targeted sequencing panels.

The pipeline is containerised with Docker and designed to be:

- reproducible  
- idempotent  
- cache-aware  
- portable across machines  

It implements a complete analysis workflow for targeted sequencing data, including:

- FASTQ ingestion from SRA
- quality control and adapter trimming
- alignment to GRCh38
- duplicate-aware BAM processing
- somatic variant calling with GATK Mutect2
- orientation bias modeling
- variant filtering and normalization
- Ensembl VEP annotation
- heuristic somatic vs germline classification
- gene-level variant summaries
- automated HTML reporting

The pipeline produces deterministic outputs and supports cache-aware re-execution, allowing repeated runs to skip previously completed stages.

---

# Pipeline Overview

```
FASTQ (SRA)
    │
    ▼
fastp QC / trimming
    │
    ▼
bwa-mem2 alignment
    │
    ▼
samtools processing
    │
    ▼
Mutect2 variant calling
    │
    ▼
LearnReadOrientationModel
    │
    ▼
FilterMutectCalls
    │
    ▼
PASS variants
    │
    ▼
VEP annotation
    │
    ▼
somatic / germline classification
    │
    ▼
gene summaries + HTML report
```

---

# Quick Start

Clone the repository:

```bash
git clone https://github.com/adegbola9898/somatic-pipeline-harness
cd somatic-pipeline-harness
```

Build the Docker environment:

```bash
docker build -f docker/Dockerfile.dev -t somatic-dev:local .
```

Create required directories:

```bash
mkdir -p refs/reference refs/targets ref_cache out
```

Download the reference bundle:

```bash
curl -L -o refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz \
https://storage.googleapis.com/somatic/somatic_refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz
```

Download checksum:

```bash
curl -L -o refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz.sha256 \
https://storage.googleapis.com/somatic/somatic_refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz.sha256
```

Download the target panel:

```bash
curl -L -o refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed \
https://storage.googleapis.com/somatic/somatic_refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed
```

Run the pipeline:

```bash
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
```

---

# Workflow Stages

## 1. FASTQ ingestion

Sequencing reads are downloaded from SRA.

Tool:

- `sra-tools`

Outputs:

- paired FASTQ files

---

## 2. Read QC and trimming

Adapters and low-quality bases are removed.

Tool:

- `fastp`

Outputs:

- cleaned FASTQ files
- fastp QC metrics

---

## 3. Alignment

Reads are aligned to the GRCh38 reference genome.

Tool:

- `bwa-mem2`

Outputs:

- aligned BAM

---

## 4. BAM processing

Standard duplicate-aware alignment processing.

Tools:

- `samtools sort`
- `samtools fixmate`
- `samtools markdup`
- `samtools index`

Outputs:

- coordinate-sorted duplicate-marked BAM
- BAM index

---

## 5. Coverage QC

Coverage statistics across the targeted panel.

Tools:

- `samtools depth`
- `bedtools`

Outputs:

- global coverage summary
- per-gene coverage metrics

---

## 6. Somatic variant calling

Candidate variants are called using Mutect2.

Tool:

- `GATK Mutect2`

Outputs:

- raw candidate VCF
- F1R2 orientation evidence

---

## 7. Orientation bias modeling

Orientation artifacts are modeled.

Tool:

- `GATK LearnReadOrientationModel`

Outputs:

- orientation bias model

---

## 8. Variant filtering

High-confidence somatic calls are filtered.

Tool:

- `GATK FilterMutectCalls`

Outputs:

- filtered VCF

---

## 9. Variant post-processing

Variants are normalized and split.

Tool:

- `bcftools norm`

Outputs:

- normalized PASS-only VCF

---

## 10. Variant table generation

PASS variants are converted to analysis tables.

Generated tables include:

- compact variant table
- annotated variant table
- classification tables
- gene-level summaries

---

## 11. Variant annotation

Variants are annotated using the **Ensembl REST VEP API**.

Annotation fields include:

- HGVS notation
- gene symbol
- transcript ID
- consequence
- SIFT
- PolyPhen
- ClinVar significance
- gnomAD allele frequency

Outputs:

```
results/reports/

SAMPLE.PASS.annotated.tsv
SAMPLE.PASS.annotated.jsonl
```

---

## 12. Somatic vs Germline classification

Variants are heuristically classified based on:

- allele fraction
- sequencing depth
- Mutect2 TLOD
- population allele frequency (gnomAD)
- ClinVar evidence

Each variant receives a final classification:

- **somaticish** — low AF candidate variants without strong germline signals  
- **germlineish** — variants with strong germline-like evidence  
- **uncertain** — variants with insufficient or conflicting evidence  

Outputs:

```
results/reports/

SAMPLE.PASS.flagged.tsv
SAMPLE.PASS.somaticish.tsv
SAMPLE.PASS.germlineish.tsv
SAMPLE.PASS.uncertain.tsv
```

These tables help prioritize variants for downstream review.

---

## 13. Gene-level summaries

Variants are aggregated per gene.

Output:

```
results/reports/

SAMPLE.gene_summary.tsv
```

Fields include:

- variant counts
- somaticish counts
- germlineish counts
- maximum allele fraction
- mean allele fraction
- maximum TLOD
- gene coverage statistics

---

## 14. HTML report

The pipeline automatically produces a summary report.

Output:

```
results/reports/

SAMPLE.report.html
```

The report includes:

- run summary
- coverage metrics
- top mutated genes
- top variants
- classification summaries

---

# Pipeline Output Structure

All outputs follow a strict directory contract.

```
OUTDIR/SAMPLE_ID/

inputs/
work/
results/
qc/
logs/
metadata/
```

Example:

```
out/DEMO1/

inputs/
logs/
metadata/
qc/
results/
work/
```

---

# Important Outputs

## BAM

```
results/bam/

SAMPLE.sorted.markdup.bam
SAMPLE.sorted.markdup.bam.bai
```

---

## Mutect2 outputs

```
results/mutect2/

SAMPLE.mutect2.unfiltered.vcf.gz
SAMPLE.mutect2.filtered.vcf.gz

SAMPLE.mutect2.f1r2.tar.gz
SAMPLE.read-orientation-model.tar.gz
```

---

## PASS variants

```
results/mutect2/

SAMPLE.PASS.norm.split.vcf.gz
SAMPLE.PASS_variants.tsv
SAMPLE.PASS_variants.perAllele.tsv
SAMPLE.PASS_count.txt
```

---

## Reports

```
results/reports/

SAMPLE.PASS.compact.tsv
SAMPLE.PASS.annotated.tsv
SAMPLE.PASS.annotated.jsonl

SAMPLE.PASS.flagged.tsv
SAMPLE.PASS.somaticish.tsv
SAMPLE.PASS.germlineish.tsv
SAMPLE.PASS.uncertain.tsv

SAMPLE.gene_summary.tsv
SAMPLE.report.html
```

---

# Reference Caching

The first run extracts reference resources into:

```
ref_cache/
```

Subsequent runs reuse cached references.

Example log:

```
SKIP step_resources (outputs present + resource shas match)
```

---

# Idempotent Pipeline Execution

Completed stages are automatically skipped.

Example warm run:

```
SKIP step_resources
SKIP step_ingest
SKIP step_fastp
SKIP step_align
SKIP step_mutect_call
SKIP step_mutect_filter
```

---

# Reproducibility

This pipeline guarantees:

- deterministic execution
- containerized runtime environment
- reference integrity verification
- cache-aware re-execution
- structured output contracts

Tested on a fresh Ubuntu WSL environment.

Cold run:

```
real 38m23s
```

Warm run:

```
real 56s
```

---

# WSL Memory Configuration

If running under WSL2, increase memory allocation.

Create:

```
%USERPROFILE%\.wslconfig
```

Example:

```
[wsl2]
memory=28GB
processors=8
swap=8GB
```

Restart WSL:

```
wsl --shutdown
```

---

# Notes

For machines with limited RAM reduce thread usage:

```
--threads 2
```

Alignment and sorting are the most memory-intensive stages.

---

# License

MIT License
