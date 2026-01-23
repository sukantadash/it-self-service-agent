#!/usr/bin/env bash
set -euo pipefail

# Simple Helm install for "test" mode (equivalent intent to `make helm-install-test`,
# but without Makefile logic).
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

echo "Updating chart dependencies..."
helm dependency update helm >/dev/null

echo "Creating/refreshing ServiceNow credentials secret (safe if left empty)..."
${KUBE} create secret generic "${RELEASE_NAME}-servicenow-credentials" \
  --from-literal=servicenow-instance-url="${SERVICENOW_INSTANCE_URL:-}" \
  --from-literal=servicenow-api-key="${SERVICENOW_API_KEY:-}" \
  -n "${NAMESPACE}" --dry-run=client -o yaml | ${KUBE} apply -f -

echo "Installing/upgrading via helm..."
HELM_SET_ARGS=(
  "--set" "requestManagement.knative.mockEventing.enabled=true"
  "--set" "testIntegrationEnabled=true"
  "--set" "mcp-servers.mcp-servers.self-service-agent-snow.envSecrets.SERVICENOW_INSTANCE_URL.name=${RELEASE_NAME}-servicenow-credentials"
  "--set" "mcp-servers.mcp-servers.self-service-agent-snow.envSecrets.SERVICENOW_INSTANCE_URL.key=servicenow-instance-url"
)

if [[ -n "${IMAGE_REGISTRY}" ]]; then
  HELM_SET_ARGS+=("--set" "image.registry=${IMAGE_REGISTRY}")
  HELM_SET_ARGS+=("--set" "mcp-servers.mcp-servers.self-service-agent-snow.image.repository=${IMAGE_REGISTRY}/self-service-agent-snow-mcp")
fi
if [[ -n "${IMAGE_TAG}" ]]; then
  HELM_SET_ARGS+=("--set" "image.tag=${IMAGE_TAG}")
  HELM_SET_ARGS+=("--set" "mcp-servers.mcp-servers.self-service-agent-snow.image.tag=${IMAGE_TAG}")
fi

helm upgrade --install "${RELEASE_NAME}" helm \
  -n "${NAMESPACE}" \
  -f "${VALUES_FILE}" \
  "${HELM_SET_ARGS[@]}"

echo ""
echo "Done."

