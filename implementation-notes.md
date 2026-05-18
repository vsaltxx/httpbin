## Development history

The implementation was done incrementally through Git commits. The commit history shows the progression from Dockerfile hardening, dependency compatibility fixes, CI security checks, GHCR publishing, Trivy scanning, raw Kubernetes manifests, the Helm chart, and finally two rounds of code review from GitHub Copilot. 

The full PR is available at: https://github.com/vsaltxx/httpbin/pull/1

Each major change was intentionally committed as a separate commit rather than squashing or rewriting history with `git rebase -i`. This makes the decision-making process and evolution of the project clearly visible in the commit log.

## Implementation Notes

Decisions that explain *why* things were built the way they were.

#### 1. Both raw manifests and Helm chart are included

The `k8s/` directory and the `chart/` directory both exist intentionally — included to demonstrate understanding of both raw Kubernetes manifests and Helm packaging. In a real production setup only the Helm chart would be kept, since it handles environment-specific configuration, templating, and upgrades cleanly. The raw manifests are useful for understanding the underlying structure but would be removed to avoid maintaining two sources of truth.

#### 2. No `Deploy to K8s` stage in the CI pipeline

The task specification explicitly said to write manifests for deployment to a **local** cluster. Adding a CI deploy step that targets a local Minikube instance would be dead code — GitHub Actions has no way to reach it. A fake or placeholder deploy job would be misleading. In a real setup with a reachable cluster, a deploy stage using `kubectl apply` or `helm upgrade --install` would be a natural next step after the image scan passes.

#### 3. Read-only root filesystem requires a writable `/tmp`

The container uses `readOnlyRootFilesystem: true` as a security hardening measure. Gunicorn requires a writable temporary directory at runtime, so the chart mounts an `emptyDir` volume at `/tmp` while keeping the rest of the root filesystem read-only. This is a deliberate trade-off — security first, with just enough writability for the runtime to function.

#### 4. Upstream codebase compatibility

The project is based on an older upstream `httpbin` codebase. Some dependency and compatibility adjustments were required to run it with the selected Python, Flask, and Werkzeug versions. The original `Pipfile.lock` was incompatible with Python 3.12, so dependencies were migrated to `requirements.txt` with updated versions, and minor fixes were applied to `core.py` and `helpers.py`.
