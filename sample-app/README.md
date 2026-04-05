# Sample Application

A lightweight Flask REST API used as the demo workload for the OCP GitOps POC.

## Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/` | GET | Returns app info (name, version, environment, message) |
| `/health` | GET | Liveness probe - returns `{"status": "healthy"}` |
| `/ready` | GET | Readiness probe - returns `{"status": "ready"}` |

## Local Development

```bash
cd sample-app
pip install -r src/requirements.txt
cd src && python app.py
# App runs at http://localhost:8080
```

## Running Tests

```bash
cd sample-app
pip install -r src/requirements.txt -r tests/requirements-test.txt
cd src && python -m pytest ../tests/ -v
```

## Docker Build

```bash
cd sample-app
docker build -t sample-app:local .
docker run -p 8080:8080 -e APP_ENV=development -e APP_VERSION=local sample-app:local
```

## Container Image

- **Registry**: ghcr.io/esarath/sample-app
- **Base**: python:3.12-slim (multi-stage build)
- **Runtime**: Gunicorn with 2 workers
- **User**: Non-root (UID 1001)
- **Port**: 8080

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `APP_VERSION` | `1.0.0` | Version displayed in API response (set via ConfigMap) |
| `APP_ENV` | `development` | Environment name (staging/production via ConfigMap) |
| `PORT` | `8080` | Server port |
