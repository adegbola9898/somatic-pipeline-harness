from app.config import validate_required_env
from fastapi import FastAPI

from app.routes.health import router as health_router
from app.routes.runs import router as runs_router

validate_required_env()

app = FastAPI(
    title="Somatic Pipeline API",
    version="0.1.0",
)

app.include_router(health_router)
app.include_router(runs_router)
