#!/usr/bin/env bash
set -euo pipefail

# Re-run init/ingestion Job by rendering `templates/init-job.yaml` and recreating it.
#
# Usage:
#   ./customer/script-run-ingestion-job.sh <namespace> <release> <valuesFile>
#
# Example:
#   ./customer/script-run-ingestion-job.sh it-self-service-agent it-self-service-agent ./helm/values-test.yaml

die() { echo "ERROR: $*" >&2; exit 1; }

NAMESPACE="${1:-}"
RELEASE="${2:-}"
VALUES_FILE="${3:-}"

[[ -n "$NAMESPACE" ]] || die "Usage: $0 <namespace> <release> <valuesFile>"
[[ -n "$RELEASE" ]] || die "Usage: $0 <namespace> <release> <valuesFile>"
[[ -n "$VALUES_FILE" ]] || die "Usage: $0 <namespace> <release> <valuesFile>"
[[ -f "$VALUES_FILE" ]] || die "valuesFile not found: $VALUES_FILE"

command -v oc >/dev/null 2>&1 || die "oc is required"
command -v helm >/dev/null 2>&1 || die "helm is required"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="$ROOT_DIR/helm"

TMP_MANIFEST="$(mktemp)"
trap 'rm -f "$TMP_MANIFEST"' EXIT

helm template "$RELEASE" "$CHART_DIR" -n "$NAMESPACE" -f "$VALUES_FILE" --show-only templates/init-job.yaml > "$TMP_MANIFEST"

# Delete + recreate so the Job actually runs again
oc delete -n "$NAMESPACE" -f "$TMP_MANIFEST" --ignore-not-found
oc apply -n "$NAMESPACE" -f "$TMP_MANIFEST"

JOB_NAME="$(awk '$1=="name:"{print $2; exit}' "$TMP_MANIFEST")"
oc wait -n "$NAMESPACE" --for=condition=complete "job/${JOB_NAME}" --timeout=30m
oc logs -n "$NAMESPACE" "job/${JOB_NAME}" --all-containers=true

