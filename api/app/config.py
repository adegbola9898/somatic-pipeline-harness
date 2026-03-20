import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    project_id: str = os.environ.get("PROJECT_ID") or os.environ.get("GOOGLE_CLOUD_PROJECT", "")
    region: str = os.environ.get("REGION", "us-central1")
    job_name: str = os.environ.get("JOB_NAME", "somatic-pipeline-job")
    runs_bucket: str = os.environ.get("RUNS_BUCKET", "")
    uploads_bucket: str = os.environ.get("UPLOADS_BUCKET", "somatic-demo-uploads")
    dataset_sra: str = os.environ.get("DATASET_SRA", "ERR7252107")
    threads: int = int(os.environ.get("THREADS", "8"))
    targets_bed: str = os.environ.get("TARGETS_BED", "/refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed")


settings = Settings()
