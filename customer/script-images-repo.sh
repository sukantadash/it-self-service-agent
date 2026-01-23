#!/usr/bin/env bash
set -euo pipefail

# Build images in OpenShift and PUSH them to an external image repo using a push secret.
#
# Prereqs:
# - Logged into OpenShift: oc whoami
# - BuildConfigs templates exist in customer/openshift/
#
# Usage:
#   export NAMESPACE=it-self-service-agent
#   export IMAGE_REPO=quay.io/my-org
#   export IMAGE_TAG=0.0.8
#   export REPO_PUSH_SECRET_NAME=repo-push-secret
#   export DOCKERCONFIGJSON='{"auths":{"quay.io":{"auth":"<base64(username:token)>"}}}'
#   ./script-images-repo.sh
#
# Options:
#   FOLLOW=1   # stream build logs (one build at a time)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NAMESPACE="${NAMESPACE:-it-self-service-agent}"
IMAGE_REPO="${IMAGE_REPO:-quay.io/rh-ai-quickstart}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REPO_PUSH_SECRET_NAME="${REPO_PUSH_SECRET_NAME:-repo-push-secret}"
DOCKERCONFIGJSON="${DOCKERCONFIGJSON:-}"
FOLLOW="${FOLLOW:-0}"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v oc >/dev/null 2>&1 || die "oc is required"
oc whoami >/dev/null 2>&1 || die "Not logged in to OpenShift (run: oc login ...)"

if [[ -z "$DOCKERCONFIGJSON" ]]; then
  die "DOCKERCONFIGJSON is required (kubernetes.io/dockerconfigjson content as a single-line JSON string)"
fi

echo "Namespace:              ${NAMESPACE}"
echo "Destination IMAGE_REPO: ${IMAGE_REPO}"
echo "IMAGE_TAG:              ${IMAGE_TAG}"
echo "Push secret:            ${REPO_PUSH_SECRET_NAME}"
echo "Repo root:              ${ROOT_DIR}"

if oc get project "${NAMESPACE}" >/dev/null 2>&1; then
  oc project "${NAMESPACE}" >/dev/null
else
  oc new-project "${NAMESPACE}"
fi

echo ""
echo "Applying push secret template..."
oc process -f "${ROOT_DIR}/customer/openshift/repo-secret-template.yaml" \
  -p "REPO_PUSH_SECRET_NAME=${REPO_PUSH_SECRET_NAME}" \
  -p "DOCKERCONFIGJSON=${DOCKERCONFIGJSON}" \
  | oc apply -n "${NAMESPACE}" -f -

echo ""
echo "Applying repo BuildConfigs template..."
oc process -f "${ROOT_DIR}/customer/openshift/buildconfigs-template-repo.yaml" \
  -p "IMAGE_REPO=${IMAGE_REPO}" \
  -p "IMAGE_TAG=${IMAGE_TAG}" \
  -p "REPO_PUSH_SECRET_NAME=${REPO_PUSH_SECRET_NAME}" \
  | oc apply -n "${NAMESPACE}" -f -

echo ""
echo "Starting builds (binary builds from local checkout -> external repo)..."

FOLLOW_FLAG=""
if [[ "${FOLLOW}" == "1" ]]; then
  FOLLOW_FLAG="--follow"
fi

oc start-build bc/ssa-request-manager-repo -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-agent-service-repo -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-integration-dispatcher-repo -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-snow-mcp-repo -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-mock-eventing-repo -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-mock-servicenow-repo -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}
oc start-build bc/ssa-promptguard-repo -n "${NAMESPACE}" --from-dir="${ROOT_DIR}" ${FOLLOW_FLAG}

echo ""
echo "Builds started."

