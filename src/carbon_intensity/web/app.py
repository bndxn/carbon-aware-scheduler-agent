from __future__ import annotations

import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from carbon_intensity.agent import run_agent

app = FastAPI(
    title="Carbon intensity agent API",
    version="0.1.0",
    description="HTTP wrapper around the GB carbon intensity agent.",
)


def _ensure_anthropic_api_key() -> None:
    if os.environ.get("ANTHROPIC_API_KEY"):
        return
    secret_arn = os.environ.get("ANTHROPIC_API_KEY_SECRET_ARN")
    if not secret_arn:
        return
    import boto3  # type: ignore[import-not-found]

    client = boto3.client("secretsmanager")
    secret = client.get_secret_value(SecretId=secret_arn)
    value = secret.get("SecretString")
    if value:
        os.environ["ANTHROPIC_API_KEY"] = value


def _cors_origins() -> list[str]:
    raw = os.environ.get("CORS_ORIGINS", "*")
    return [o.strip() for o in raw.split(",") if o.strip()]


app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins(),
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1)


class ChatResponse(BaseModel):
    reply: str


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/chat", response_model=ChatResponse)
def chat(body: ChatRequest) -> ChatResponse:
    _ensure_anthropic_api_key()
    reply = run_agent(body.message)
    return ChatResponse(reply=reply)
