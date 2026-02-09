#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Namespace (OpenShift project)
# -----------------------------
export NAMESPACE="${NAMESPACE:-it-self-service-agent}"

# -----------------------------
# BuildConfigs (build images in-cluster)
# -----------------------------
# IMAGE_TAG controls the ImageStreamTag outputs created by the template.
# Example:
#   IMAGE_TAG=0.0.8 ./script-images.sh
export IMAGE_TAG="${IMAGE_TAG:-latest}"

# This script lives in customer/, but the build context must be the repo root.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Using namespace: ${NAMESPACE}"
echo "Using IMAGE_TAG: ${IMAGE_TAG}"
echo "Repo root:       ${ROOT_DIR}"

if oc get project "${NAMESPACE}" >/dev/null 2>&1; then
  oc project "${NAMESPACE}" >/dev/null
else
  oc new-project "${NAMESPACE}"
fi

echo ""
echo "Applying ImageStreams + BuildConfigs..."
oc process -f "${ROOT_DIR}/customer/openshift/buildconfigs-template.yaml" -p IMAGE_TAG="${IMAGE_TAG}" | oc apply -n "${NAMESPACE}" -f -

echo ""
echo "Starting builds (binary builds from local checkout)..."

# Set FOLLOW=1 to stream build logs for each build.
FOLLOW="${FOLLOW:-0}"
FOLLOW_FLAG=""
if [[ "${FOLLOW}" == "1" ]]; then
  FOLLOW_FLAG="--follow"
fi

oc start-build bc/ssa-request-manager -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-agent-service -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-integration-dispatcher -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-snow-mcp -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-mock-eventing -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-mock-servicenow -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-promptguard -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}

echo ""
echo "Builds started."

# -----------------------------
# (Optional) Runtime env examples
# Keep these commented; set via `oc set env` or Helm values instead.
# -----------------------------
#
# export LLM=...
# export LLM_ID=...
# export LLM_URL=...
# export LLM_API_TOKEN=...
# export HF_TOKEN=...
