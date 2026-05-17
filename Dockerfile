FROM python:3.12-slim AS builder

WORKDIR /httpbin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    build-essential \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /venv
ENV PATH="/venv/bin:$PATH"

RUN pip install --no-cache-dir --upgrade pip setuptools wheel

COPY requirements.txt ./

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN pip install --no-cache-dir --no-deps .

RUN find /venv -type d -name "__pycache__" -prune -exec rm -rf {} + \
    && find /venv -type f -name "*.pyc" -delete \
    && find /venv -type f -name "*.pyo" -delete

FROM python:3.12-slim AS runtime

LABEL org.opencontainers.image.title="httpbin" \
    org.opencontainers.image.version="0.9.2" \
    org.opencontainers.image.description="A simple HTTP request and response service." \
    org.opencontainers.image.vendor="vsaltxx" \
    org.opencontainers.image.authors="Kenneth Reitz" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.source="https://github.com/vsaltxx/httpbin"

ENV PATH="/venv/bin:$PATH" \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

WORKDIR /httpbin

RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -u 1000 -m appuser

COPY --from=builder /venv /venv
COPY --from=builder /httpbin /httpbin

USER 1000
EXPOSE 8080

CMD ["gunicorn", "-b", "0.0.0.0:8080", "httpbin:app", "-k", "gevent"]
