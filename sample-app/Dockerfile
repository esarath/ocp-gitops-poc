FROM python:3.12-slim AS builder
WORKDIR /build
COPY src/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
LABEL maintainer="sarrathbabu" \
      app="sample-app"
RUN useradd -r -u 1001 appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY src/ .
USER 1001
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "app:app"]
