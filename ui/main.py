import os, time, uuid
from typing import Dict, Any

import requests
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, StreamingResponse, JSONResponse
from google.auth import default
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.cloud import storage

PROJECT_ID = os.environ["PROJECT_ID"]
REGION = os.environ["REGION"]
JOB_NAME = os.environ["JOB_NAME"]
RUNS_BUCKET = os.environ["RUNS_BUCKET"]

DATASET_SRA = os.environ.get("DATASET_SRA", "ERR7252107")
THREADS = int(os.environ.get("THREADS", "8"))

app = FastAPI()
gcs = storage.Client()

def run_jobs_url():
    return f"https://run.googleapis.com/v2/projects/{PROJECT_ID}/locations/{REGION}/jobs/{JOB_NAME}:run"

def get_access_token():
    creds, _ = default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    creds.refresh(GoogleAuthRequest())
    return creds.token

def gcs_exists(path: str) -> bool:
    return gcs.bucket(RUNS_BUCKET).blob(path).exists()

def gcs_read_text(path: str) -> str:
    blob = gcs.bucket(RUNS_BUCKET).blob(path)
    if not blob.exists():
        raise FileNotFoundError(path)
    return blob.download_as_text()

def parse_tsv_kv(tsv: str) -> Dict[str, str]:
    lines = [l.strip() for l in tsv.splitlines() if l.strip()]
    out = {}
    for l in lines[1:]:
        parts = l.split("\t")
        if len(parts) >= 2:
            out[parts[0]] = parts[1]
    return out

@app.get("/", response_class=HTMLResponse)
def index():
    return """
    <html>
    <body style="font-family:Arial; margin:40px;">
      <h2>Somatic Pipeline Demo</h2>
      <button onclick="startRun()">Analyze example dataset</button>
      <div id="status" style="margin-top:20px;"></div>
      <div id="results" style="margin-top:20px;"></div>

    <script>
    let runId = null;

    async function startRun() {
        document.getElementById("results").innerHTML = "";
        document.getElementById("status").innerHTML = "Starting...";
        const resp = await fetch("/runs", { method: "POST" });
        const data = await resp.json();
        runId = data.run_id;
        poll();
    }

    async function poll() {
        if (!runId) return;
        const resp = await fetch(`/runs/${runId}`);
        const data = await resp.json();

        document.getElementById("status").innerHTML =
          "Run ID: <b>" + runId + "</b><br>Status: <b>" + data.status + "</b>";

        if (data.status === "COMPLETE") {
            const r = data.results;
            document.getElementById("results").innerHTML =
              "<h3>Results</h3>" +
              "<div><b>QC gate:</b> " + (r.qc_gate_overall || "UNKNOWN") + "</div>" +
              "<div><b>Mean depth:</b> " + (r.mean_depth || "NA") + "</div>" +
              "<div><b>% ≥100x:</b> " + (r.pct_ge_100x || "NA") + "</div>" +
              "<div><b>PASS variants:</b> " + (r.pass_variants || "NA") + "</div>";
            return;
        }

        setTimeout(poll, 5000);
    }
    </script>
    </body>
    </html>
    """

@app.post("/runs")
def create_run():
    run_id = f"DEMO_{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
    token = get_access_token()

    args = [
        "--sample-id", run_id,
        "--sra", DATASET_SRA,
        "--ref-bundle-dir", "/refs/reference",
        "--targets-bed", "/refs/targets/targets-34genes-ensembl115-v1.gene_labeled_pad10.bed",
        "--outdir", "/out",
        "--threads", str(THREADS),
        "--enforce-qc-gate", "1",
    ]

    body = {"overrides": {"containerOverrides": [{"args": args}]}}
    resp = requests.post(run_jobs_url(), json=body,
                         headers={"Authorization": f"Bearer {token}"}, timeout=30)

    if resp.status_code >= 300:
        raise HTTPException(status_code=500, detail=resp.text)

    return {"run_id": run_id}

@app.get("/runs/{run_id}")
def get_run(run_id: str):
    qc_gate_path = f"{run_id}/qc/qc_gate.tsv"
    cov_path = f"{run_id}/qc/coverage_summary.tsv"
    pass_count_path = f"{run_id}/results/mutect2/{run_id}.PASS_count.txt"

    if gcs_exists(qc_gate_path) and gcs_exists(cov_path) and gcs_exists(pass_count_path):
        cov = parse_tsv_kv(gcs_read_text(cov_path))
        pass_count = gcs_read_text(pass_count_path).strip()

        return JSONResponse({
            "status": "COMPLETE",
            "results": {
                "qc_gate_overall": "SEE FILE",
                "mean_depth": cov.get("mean_depth"),
                "pct_ge_100x": cov.get("pct_ge_100x"),
                "pass_variants": pass_count.split()[-1]
            }
        })

    return JSONResponse({"status": "RUNNING"})
