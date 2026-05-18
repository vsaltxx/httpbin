# httpbin — DevOps Deployment

This repository contains a DevOps-oriented fork of [`httpbin`](https://github.com/postmanlabs/httpbin). The application itself is not the focus — the goal was to take an existing Python/Flask service and build everything around it: a hardened Docker image, a full CI security pipeline, and a production-ready Kubernetes deployment with Helm.

The original codebase relied on a `Pipfile.lock` that wasn't compatible with Python 3.12, so dependencies were migrated to `requirements.txt` and updated to currently working versions. A few compatibility fixes were also made to `core.py` and `helpers.py`.

Repository: https://github.com/vsaltxx/httpbin

---

## Running locally with Docker

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running

### Build and run

```bash
docker build -t httpbin-local .
docker run --rm -p 8080:8080 httpbin-local
```

Then in another terminal:

```bash
curl http://localhost:8080/get
```

The image uses a **multi-stage build** — the builder stage compiles dependencies in a virtual environment, and the runtime stage copies only the venv into a clean `python:3.12-slim` image. The container runs as a non-root user (`UID 1000`) with a read-only root filesystem. Gunicorn needs a writable `/tmp`, so that's mounted as an `emptyDir` volume in Kubernetes (or just available on your host when running with Docker).

---

## Kubernetes local deployment

### Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/) or any local Kubernetes cluster (kind, Docker Desktop, etc.)
- `kubectl` configured to point to your local cluster
- [Helm](https://helm.sh/docs/intro/install/) (required for the Helm-based deployment)
- `metrics-server` enabled (required for HPA)

### Deploy with raw manifests

```bash
minikube start
minikube addons enable metrics-server

# Create the secret manually — never stored in Git
kubectl create secret generic httpbin-secret \
  --from-literal=HTTPBIN_SECRET_KEY="$(openssl rand -hex 32)"

# Apply k8s manifests in order
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/networkpolicy.yaml

# Forward the service port locally
kubectl port-forward svc/httpbin 8080:80
```

Then test it from another terminal:

```bash
curl http://localhost:8080/get
```

Expected response:

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "localhost:8080",
    "User-Agent": "curl/..."
  },
  "origin": "127.0.0.1",
  "url": "http://localhost:8080/get"
}
```

### Deploy with Helm (alternative)

```bash
# Create the secret first (same as above)
kubectl create secret generic httpbin-secret \
  --from-literal=HTTPBIN_SECRET_KEY="$(openssl rand -hex 32)"

helm install httpbin ./chart/httpbin
```

The Helm chart exposes the same configuration through `values.yaml` — replica count, image tag, HPA limits, NetworkPolicy toggle, and security contexts.

---

## CI pipeline

The pipeline runs on every push to `master` and is structured as a sequential chain of gates — each job must pass before the next one starts.

| Step | Tool | What it checks |
|---|---|---|
| **Lint** | `ruff` | Syntax errors and obviously broken code (E9, F63, F7, F82 rules). Fast feedback before anything else runs. |
| **Test** | `pytest` | Unit tests against the actual application endpoints. |
| **SAST** | `bandit` | Static security analysis of the Python source. Fails on MEDIUM and above. Some LOW findings are left in place intentionally — they relate to `httpbin`'s design (demo auth endpoints, test passwords in URLs, etc.). |
| **Dependency audit** | `pip-audit` | Checks `requirements.txt` against known CVE databases. Fails if any vulnerable package has a patched version available. |
| **Secret scan** | `gitleaks` | Scans the full Git history for accidentally committed secrets or credentials. Uses `fetch-depth: 0` to cover all commits, not just the latest. |
| **Build & push** | `docker/build-push-action` | Builds the image and pushes it to GHCR tagged with both `latest` and the commit SHA. |
| **Image scan** | `trivy` | Scans the pushed image for OS and library vulnerabilities. Only fails on HIGH/CRITICAL findings **that have a fix available** (`--ignore-unfixed`). See Known issues below for why. |

`pip` dependencies are cached between runs using `actions/setup-python` to keep the pipeline fast. Repeated setup steps (checkout, Python setup) are shared via YAML anchors to avoid duplication.

---

## Known Issues / Trade-offs


- The raw `k8s/` manifests and Helm `values.yaml` default to the `latest` tag for convenience. For real deployments you'd pin to the immutable SHA tag that gets created on every build, so rollbacks are reliable and you know exactly what's running.

- The runtime image uses `python:3.12-slim` instead of a distroless image. This keeps     debugging and dependency compatibility simpler, but a distroless image could reduce the runtime attack surface further. The slim image still ships some Debian packages that Trivy flags as HIGH (ncurses, libtinfo) — none of them have an upstream fix yet, which is why `--ignore-unfixed` is used in the scan.

- Several low-severity Bandit findings exist in the original `httpbin` code — things like hardcoded demo credentials in URL parameters and pseudo-random number generation for test responses. These are intentional by design in `httpbin` and aren't real security risks in context, so they were left as-is rather than suppressing findings or rewriting core application behaviour.

- `HTTPBIN_SECRET_KEY` is created manually with `kubectl create secret` and never stored in Git. That's fine for local use, but production would need a proper secrets management solution. The `k8s/secret.example.yaml` file shows the expected structure, though this configuration is never actually applied in the current scenario — it's included purely for demonstration.

For more details about implementation decisions and trade-offs, see [implementation-notes.md](./implementation-notes.md).

---

## License:

This project is a fork of `postmanlabs/httpbin` and keeps the upstream ISC License.
See the `LICENSE` file for details.
