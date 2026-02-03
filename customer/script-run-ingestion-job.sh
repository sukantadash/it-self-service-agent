#!/usr/bin/env bash
set -euo pipefail

# Manually run the "ingestion" job (the Helm init Job) on demand.
#
# This job runs: `python -m agent_service.scripts.register_assets`
# which registers agents + knowledge bases with LlamaStack (and ingests KB docs).
#
# Usage:
#   export NAMESPACE=it-self-service-agent
#   export RELEASE=it-self-service-agent-sukanta
#   # If you installed with a values file, pass it again so the rendered job matches your release:
#   export VALUES_FILE=/path/to/values-test.yaml
#   ./customer/script-run-ingestion-job.sh
#
# Options:
#   CHART_DIR=/path/to/helm                 # default: <repo>/helm
#   VALUES_FILE=/path/to/values.yaml        # optional (can also pass VALUES_FILES="a.yaml b.yaml")
#   VALUES_FILES="/a.yaml /b.yaml"          # optional (space-separated)
#   TIMEOUT=30m                             # default: 30m
#   FOLLOW_LOGS=1                           # default: 1

die() { echo "ERROR: $*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-it-self-service-agent}"
RELEASE="${RELEASE:-}"
CHART_DIR="${CHART_DIR:-$ROOT_DIR/helm}"
VALUES_FILE="${VALUES_FILE:-}"
VALUES_FILES="${VALUES_FILES:-}"
TIMEOUT="${TIMEOUT:-30m}"
FOLLOW_LOGS="${FOLLOW_LOGS:-1}"

if command -v oc >/dev/null 2>&1; then
  K=oc
elif command -v kubectl >/dev/null 2>&1; then
  K=kubectl
else
  die "Need oc or kubectl in PATH"
fi

command -v helm >/dev/null 2>&1 || die "helm is required"
[[ -n "$RELEASE" ]] || die "Set RELEASE (Helm release name)"
[[ -d "$CHART_DIR" ]] || die "CHART_DIR not found: $CHART_DIR"

VALUES_ARGS=()
if [[ -n "$VALUES_FILE" ]]; then
  [[ -f "$VALUES_FILE" ]] || die "VALUES_FILE not found: $VALUES_FILE"
  VALUES_ARGS+=(-f "$VALUES_FILE")
fi
if [[ -n "$VALUES_FILES" ]]; then
  for f in $VALUES_FILES; do
    [[ -f "$f" ]] || die "VALUES_FILES entry not found: $f"
    VALUES_ARGS+=(-f "$f")
  done
fi

echo "Namespace: $NAMESPACE"
echo "Release:   $RELEASE"
echo "Chart:     $CHART_DIR"
echo "CLI:       $K"
echo ""

TMP_MANIFEST="$(mktemp)"
trap 'rm -f "$TMP_MANIFEST"' EXIT

echo "Rendering init-job from Helm chart..."
helm template "$RELEASE" "$CHART_DIR" -n "$NAMESPACE" "${VALUES_ARGS[@]}" --show-only templates/init-job.yaml > "$TMP_MANIFEST"

ORIG_JOB_NAME="$(awk '
  $1=="metadata:" {inmeta=1; next}
  inmeta && $1=="name:" {print $2; exit}
' "$TMP_MANIFEST")"
[[ -n "$ORIG_JOB_NAME" ]] || die "Could not determine init job name from rendered manifest"

TS="$(date +%Y%m%d%H%M%S)"
NEW_JOB_NAME="${ORIG_JOB_NAME}-manual-${TS}"

echo "Creating job: $NEW_JOB_NAME"

awk -v old="  name: ${ORIG_JOB_NAME}" -v new="  name: ${NEW_JOB_NAME}" '
  !done && $0==old {print new; done=1; next}
  {print}
' "$TMP_MANIFEST" | $K apply -n "$NAMESPACE" -f -

echo "Waiting for job completion (timeout: $TIMEOUT)..."
$K wait -n "$NAMESPACE" --for=condition=complete "job/${NEW_JOB_NAME}" --timeout="$TIMEOUT"

if [[ "$FOLLOW_LOGS" == "1" ]]; then
  echo ""
  echo "Job logs:"
  $K logs -n "$NAMESPACE" "job/${NEW_JOB_NAME}" --all-containers=true
fi

echo ""
echo "Done."

