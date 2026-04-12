# syntax=docker/dockerfile:1
FROM python:3.12-slim-bookworm

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:$PATH"

COPY pyproject.toml uv.lock README.md app.py ./
COPY src ./src

RUN uv sync --frozen --no-dev

EXPOSE 8000

CMD ["uvicorn", "carbon_intensity.web.app:app", "--host", "0.0.0.0", "--port", "8000"]
