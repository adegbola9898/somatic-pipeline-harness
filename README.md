# Somatic Pipeline Harness

A deterministic somatic variant calling pipeline for targeted sequencing panels.

The pipeline is containerised with Docker and designed to be:

- reproducible
- idempotent
- cache-aware
- portable across machines

The goal of this project is to provide a clean, deterministic harness for targeted somatic variant analysis with strong reproducibility guarantees.

---

# Workflow Overview

The pipeline performs the following stages.

## 1. FASTQ ingestion
Sequencing data is downloaded directly from SRA.

Tools used:
- `sra-tools`

Outputs:
- paired FASTQ files

---

## 2. Read QC and trimming

Adapter trimming and quality filtering.

Tool:
- `fastp`

Outputs:
- cleaned FASTQ files
- fastp QC metrics

---

## 3. Alignment

Reads are aligned to GRCh38 using the high-performance BWA implementation.

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

Somatic candidate variants are called with Mutect2.

Tool:
- `GATK Mutect2`

Outputs:
- raw candidate VCF
- F1R2 orientation evidence

---

## 7. Orientation bias modeling

Mutect2 orientation artifacts are modeled.

Tool:
- `GATK LearnReadOrientationModel`

Outputs:
- orientation bias model

---

## 8. Variant filtering

Filtered high-confidence variants.

Tool:
- `GATK FilterMutectCalls`

Outputs:
- filtered VCF

---

## 9. Variant post-processing

Variants are normalised and decomposed.

Tools:
- `bcftools norm`

Outputs:
- split multi-allelic variants
- PASS-only VCF

---

## 10. Variant table generation

PASS variants are converted into analysis-ready tables.

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
- most severe consequence
- gene symbol
- transcript ID
- predicted impact
- SIFT
- PolyPhen
- ClinVar significance
- gnomAD population allele frequency

Outputs:


results/reports/
SAMPLE.PASS.annotated.tsv
SAMPLE.PASS.annotated.jsonl


---

## 12. Somatic vs Germline classification

Variants are heuristically classified based on:

- allele fraction
- depth
- Mutect2 TLOD
- gnomAD population frequency
- ClinVar evidence

Outputs:


results/reports/

SAMPLE.PASS.flagged.tsv
SAMPLE.PASS.somaticish.tsv
SAMPLE.PASS.germlineish.tsv

These tables highlight candidate somatic variants for review.

---

## 13. Gene-level summaries

Variant results are aggregated per gene.

Output:


results/reports/

SAMPLE.gene_summary.tsv

Fields include:

- variant counts per gene
- somaticish counts
- germlineish counts
- maximum allele fraction
- mean allele fraction
- maximum TLOD
- gene mean coverage
- percent of bases ≥100× coverage

---

## 14. HTML report generation

The pipeline automatically produces a **one-page HTML report** summarising the run.

Output:


results/reports/

SAMPLE.report.html

The report includes:

- run summary
- coverage metrics
- top mutated genes
- top variants
- variant classifications

This allows rapid inspection without opening multiple TSV files.

---

# Pipeline Output Structure

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

---

# Important Outputs

## BAM


results/bam/

SAMPLE.sorted.markdup.bam
SAMPLE.sorted.markdup.bam.bai

---

## Mutect2 Outputs


results/mutect2/

SAMPLE.mutect2.unfiltered.vcf.gz
SAMPLE.mutect2.unfiltered.vcf.gz.tbi

SAMPLE.mutect2.filtered.vcf.gz
SAMPLE.mutect2.filtered.vcf.gz.tbi

SAMPLE.mutect2.stats

SAMPLE.mutect2.f1r2.tar.gz
SAMPLE.read-orientation-model.tar.gz

These correspond to the Mutect2 orientation bias workflow:


Mutect2
→ LearnReadOrientationModel
→ FilterMutectCalls (--ob-priors)


---

## PASS Variant Outputs


results/mutect2/

SAMPLE.PASS.norm.split.vcf.gz
SAMPLE.PASS.norm.split.vcf.gz.csi

SAMPLE.PASS_variants.tsv
SAMPLE.PASS_variants.perAllele.tsv

SAMPLE.PASS_count.txt

These represent high-confidence PASS variants.

---

## Report Outputs


results/reports/

SAMPLE.PASS.compact.tsv
SAMPLE.PASS.annotated.tsv
SAMPLE.PASS.annotated.jsonl

SAMPLE.PASS.flagged.tsv
SAMPLE.PASS.somaticish.tsv
SAMPLE.PASS.germlineish.tsv

SAMPLE.gene_summary.tsv

SAMPLE.report.html

---

## QC Outputs


qc/

coverage_summary.tsv
per_gene_coverage.tsv
SAMPLE.flagstat.txt

These summarise:

- mean coverage
- coverage thresholds
- per-gene coverage
- alignment statistics

---

# Fetch Reference Bundle

Create required directories:

```bash
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

If the download is interrupted:

curl -L -C - -o refs/reference/refs-grch38-bwamem2-r115-v1.tar.gz
Build Docker Environment
docker build -f docker/Dockerfile.dev -t somatic-dev:local .
Run the Pipeline

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
Reference Caching

The first run extracts the reference bundle into:

ref_cache/

Subsequent runs reuse this cache.

Example log:

SKIP step_resources (outputs present + resource shas match)
Idempotent Pipeline Execution

Completed stages are automatically skipped.

Example warm run:

SKIP step_resources
SKIP step_ingest
SKIP step_fastp
SKIP step_align
SKIP step_qc_gate
SKIP step_mutect_call
SKIP step_learn_read_orientation_model
SKIP step_mutect_filter
SKIP step_postprocess_pass
Reproducibility Test

Tested on a fresh Ubuntu WSL environment.

Cold run:

real 38m23s

Warm run:

real 56s

Demonstrates:

deterministic outputs

reference caching

idempotent execution

WSL Memory Configuration

If running under WSL2, increase memory allocation to avoid OOM during alignment.

Create:

%USERPROFILE%\.wslconfig

Example:

[wsl2]
memory=28GB
processors=8
swap=8GB

Restart WSL:

wsl --shutdown
Notes

For machines with limited RAM reduce threads:

--threads 2

Alignment and sorting are the most memory-intensive stages.

What This Pipeline Guarantees

deterministic execution

containerised environment

reference integrity verification

cache-aware execution

structured output contract

reproducible somatic variant analysis
