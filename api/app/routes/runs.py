from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["runs"])


@router.get("/", response_class=HTMLResponse)
def index() -> str:
    return """
    <html>
      <body style="font-family: Arial; margin: 40px;">
        <h2>Somatic Pipeline API</h2>
        <p>API skeleton is live.</p>
        <ul>
          <li><a href="/health">Health check</a></li>
        </ul>
      </body>
    </html>
    """


@router.post("/runs")
def create_run() -> dict:
    return {
        "message": "Run creation route not implemented yet",
        "status": "placeholder",
    }


@router.get("/runs/{run_id}")
def get_run(run_id: str) -> dict:
    return {
        "run_id": run_id,
        "status": "placeholder",
        "message": "Run lookup route not implemented yet",
    }
