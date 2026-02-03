#!/usr/bin/env bash
set -euo pipefail

# Simple Helm install for "test" mode (equivalent intent to `make helm-install-test`,
# but without Makefile logic).
#
# This installer assumes these dependencies are ALREADY present in the OpenShift cluster
# (installed/managed outside this Helm release):
# - pgvector (PostgreSQL)
# - llama-stack
# - llm-service
# - mcp-servers
#
# Placeholders you can provide (via env vars):
#
# - **PostgreSQL/pgvector connection** (required; creates/updates `Secret/pgvector`)
#   - PGVECTOR_HOST
#   - PGVECTOR_PORT (default: 5432)
#   - PGVECTOR_DBNAME (default: postgres)
#   - PGVECTOR_USER
#   - PGVECTOR_PASSWORD
#
# - **LlamaStack connection** (optional; passed to Helm values)
#   - LLAMA_STACK_URL (example: http://llamastack.<ns>.svc.cluster.local:8321)
#   - LLAMASTACK_API_KEY
#   - LLAMASTACK_CLIENT_PORT
#   - LLAMASTACK_OPENAI_BASE_PATH (default in values.yaml is usually `/v1/openai/v1`)
#   - LLAMASTACK_TIMEOUT
#
# - **ServiceNow connection** (optional; creates/updates `${RELEASE_NAME}-servicenow-credentials`)
#   - SERVICENOW_INSTANCE_URL
#   - SERVICENOW_API_KEY
#
# Usage:
#   export NAMESPACE=it-self-service-agent
#   ./sprint-install.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-it-self-service-agent}"
RELEASE_NAME="${RELEASE_NAME:-self-service-agent}"
VALUES_FILE="${VALUES_FILE:-helm/values-test.yaml}"

# Optional image overrides (defaults come from helm/values.yaml)
IMAGE_REGISTRY="${IMAGE_REGISTRY:-}"
IMAGE_TAG="${IMAGE_TAG:-}"

# External dependency connection details
PGVECTOR_HOST="${PGVECTOR_HOST:-}"
PGVECTOR_PORT="${PGVECTOR_PORT:-5432}"
PGVECTOR_DBNAME="${PGVECTOR_DBNAME:-postgres}"
PGVECTOR_USER="${PGVECTOR_USER:-}"
PGVECTOR_PASSWORD="${PGVECTOR_PASSWORD:-}"

LLAMA_STACK_URL="${LLAMA_STACK_URL:-}"
LLAMASTACK_API_KEY="${LLAMASTACK_API_KEY:-}"
LLAMASTACK_CLIENT_PORT="${LLAMASTACK_CLIENT_PORT:-}"
LLAMASTACK_OPENAI_BASE_PATH="${LLAMASTACK_OPENAI_BASE_PATH:-}"
LLAMASTACK_TIMEOUT="${LLAMASTACK_TIMEOUT:-}"

# Use kubectl if available; otherwise fall back to oc
KUBE="${KUBE_TOOL:-kubectl}"
if ! command -v "${KUBE}" >/dev/null 2>&1; then
  KUBE="oc"
fi

echo "Repo root:  ${ROOT_DIR}"
echo "NAMESPACE:  ${NAMESPACE}"
echo "RELEASE:    ${RELEASE_NAME}"
echo "VALUES:     ${VALUES_FILE}"
echo ""

cd "${ROOT_DIR}"

echo "Ensuring namespace exists..."
${KUBE} create namespace "${NAMESPACE}" --dry-run=client -o yaml | ${KUBE} apply -f -

if [[ -z "${PGVECTOR_HOST}" || -z "${PGVECTOR_USER}" || -z "${PGVECTOR_PASSWORD}" ]]; then
  cat >&2 <<'EOF'
Missing required pgvector/PostgreSQL connection details.

Set these env vars and re-run:
  export PGVECTOR_HOST="..."
  export PGVECTOR_USER="..."
  export PGVECTOR_PASSWORD="..."

Optional:
  export PGVECTOR_PORT="5432"
  export PGVECTOR_DBNAME="postgres"
EOF
  exit 2
fi

echo "Creating/refreshing pgvector connection secret (required by this chart)..."
${KUBE} create secret generic "pgvector" \
  --from-literal=host="${PGVECTOR_HOST}" \
  --from-literal=port="${PGVECTOR_PORT}" \
  --from-literal=dbname="${PGVECTOR_DBNAME}" \
  --from-literal=user="${PGVECTOR_USER}" \
  --from-literal=password="${PGVECTOR_PASSWORD}" \
  -n "${NAMESPACE}" --dry-run=client -o yaml | ${KUBE} apply -f -

echo "Creating/refreshing ServiceNow credentials secret (safe if left empty)..."
${KUBE} create secret generic "${RELEASE_NAME}-servicenow-credentials" \
  --from-literal=servicenow-instance-url="${SERVICENOW_INSTANCE_URL:-}" \
  --from-literal=servicenow-api-key="${SERVICENOW_API_KEY:-}" \
  -n "${NAMESPACE}" --dry-run=client -o yaml | ${KUBE} apply -f -

echo "Installing/upgrading via helm..."
HELM_SET_ARGS=(
  "--set" "requestManagement.knative.mockEventing.enabled=true"
  "--set" "testIntegrationEnabled=true"
)

if [[ -n "${LLAMA_STACK_URL}" ]]; then
  HELM_SET_ARGS+=("--set" "llama_stack_url=${LLAMA_STACK_URL}")
fi
if [[ -n "${LLAMASTACK_API_KEY}" ]]; then
  HELM_SET_ARGS+=("--set" "llamastack.apiKey=${LLAMASTACK_API_KEY}")
fi
if [[ -n "${LLAMASTACK_CLIENT_PORT}" ]]; then
  HELM_SET_ARGS+=("--set" "llamastack.port=${LLAMASTACK_CLIENT_PORT}")
fi
if [[ -n "${LLAMASTACK_OPENAI_BASE_PATH}" ]]; then
  HELM_SET_ARGS+=("--set" "llamastack.openaiBasePath=${LLAMASTACK_OPENAI_BASE_PATH}")
fi
if [[ -n "${LLAMASTACK_TIMEOUT}" ]]; then
  HELM_SET_ARGS+=("--set" "llamastack.timeout=${LLAMASTACK_TIMEOUT}")
fi

if [[ -n "${IMAGE_REGISTRY}" ]]; then
  HELM_SET_ARGS+=("--set" "image.registry=${IMAGE_REGISTRY}")
fi
if [[ -n "${IMAGE_TAG}" ]]; then
  HELM_SET_ARGS+=("--set" "image.tag=${IMAGE_TAG}")
fi

helm upgrade --install "${RELEASE_NAME}" helm \
  -n "${NAMESPACE}" \
  -f "${VALUES_FILE}" \
  "${HELM_SET_ARGS[@]}"

echo ""
echo "Done."

