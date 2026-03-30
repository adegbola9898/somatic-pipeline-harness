from app.config import validate_required_env
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routes.health import router as health_router
from app.routes.runs import router as runs_router

validate_required_env()

app = FastAPI(
    title="Somatic Pipeline API",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://60bb4b4deb26f6cf-dot-us-central1.notebooks.googleusercontent.com",
        "https://somatic-pipeline-ui-31752759845.us-central1.run.app",
    ],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(runs_router)
