#!/usr/bin/env bash
set -euo pipefail

# Sync local `agent-service/config/` into the agent-service config PVC.
#
# Why:
# - When `requestManagement.agentService.configPersistence.enabled=true`, Helm mounts a PVC at:
#     /app/agent-service/config
#   for BOTH:
#   - the agent-service Deployment
#   - the init Job (the "ingestion" job) that registers/ingests knowledge bases
#
# This script lets you update the PVC contents without rebuilding images.
#
# Usage:
#   export NAMESPACE=it-self-service-agent
#   export RELEASE=it-self-service-agent-sukanta
#   ./customer/script-sync-agent-config-to-pvc.sh
#
# Options:
#   SRC_DIR=/path/to/agent-service/config     # default: <repo>/agent-service/config
#   PVC_NAME=<pvc name>                      # default: computed from RELEASE + Chart.yaml name
#   POD_NAME=ssa-config-sync                 # default: ssa-config-sync
#   MOUNT_PATH=/mnt/config                   # default: /mnt/config
#   CLEANUP=1                                # default: 1 (delete helper pod after sync)
#   KEEP_EXISTING=0                          # default: 0 (wipe PVC dir before copy)

die() { echo "ERROR: $*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NAMESPACE="${NAMESPACE:-it-self-service-agent}"
RELEASE="${RELEASE:-}"
SRC_DIR="${SRC_DIR:-$ROOT_DIR/agent-service/config}"
POD_NAME="${POD_NAME:-ssa-config-sync}"
MOUNT_PATH="${MOUNT_PATH:-/mnt/config}"
CLEANUP="${CLEANUP:-1}"
KEEP_EXISTING="${KEEP_EXISTING:-0}"

if command -v oc >/dev/null 2>&1; then
  K=oc
elif command -v kubectl >/dev/null 2>&1; then
  K=kubectl
else
  die "Need oc or kubectl in PATH"
fi

[[ -d "$SRC_DIR" ]] || die "SRC_DIR not found: $SRC_DIR"

if [[ -z "${PVC_NAME:-}" ]]; then
  [[ -n "$RELEASE" ]] || die "Set RELEASE or PVC_NAME"

  # Compute Helm fullname using the same logic as templates/_helpers.tpl:
  # - Chart name from helm/Chart.yaml
  # - If RELEASE contains chart name, fullname = RELEASE else fullname = RELEASE-chartName
  CHART_NAME="$(awk -F': ' '$1=="name"{print $2; exit}' "$ROOT_DIR/helm/Chart.yaml" | tr -d '[:space:]')"
  [[ -n "$CHART_NAME" ]] || die "Could not read chart name from $ROOT_DIR/helm/Chart.yaml"

  if [[ "$RELEASE" == *"$CHART_NAME"* ]]; then
    FULLNAME="$RELEASE"
  else
    FULLNAME="${RELEASE}-${CHART_NAME}"
  fi

  PVC_NAME="${FULLNAME}-agent-service-config"
fi

echo "Namespace:   $NAMESPACE"
echo "PVC:         $PVC_NAME"
echo "Source dir:  $SRC_DIR"
echo "Helper pod:  $POD_NAME"
echo "Mount path:  $MOUNT_PATH"
echo "CLI:         $K"
echo ""

echo "Ensuring PVC exists..."
$K get pvc "$PVC_NAME" -n "$NAMESPACE" >/dev/null

echo "Creating/updating helper pod..."
cat <<YAML | $K apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  labels:
    app.kubernetes.io/name: ssa-config-sync
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: sync
      image: registry.access.redhat.com/ubi9/ubi:latest
      command: ["bash","-lc","sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      volumeMounts:
        - name: cfg
          mountPath: ${MOUNT_PATH}
  volumes:
    - name: cfg
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
YAML

echo "Waiting for helper pod to be Ready..."
$K wait -n "$NAMESPACE" --for=condition=Ready "pod/${POD_NAME}" --timeout=120s

if [[ "$KEEP_EXISTING" == "0" ]]; then
  echo "Clearing existing files in PVC mount..."
  $K exec -n "$NAMESPACE" "${POD_NAME}" -- bash -lc "rm -rf '${MOUNT_PATH:?}'/* '${MOUNT_PATH:?}'/.[!.]* '${MOUNT_PATH:?}'/..?* 2>/dev/null || true"
fi

echo "Copying files (tar stream) ..."
tar -C "$SRC_DIR" -cf - . | $K exec -i -n "$NAMESPACE" "${POD_NAME}" -- tar -C "$MOUNT_PATH" -xf -

echo "Sync complete."

if [[ "$CLEANUP" == "1" ]]; then
  echo "Cleaning up helper pod..."
  $K delete pod -n "$NAMESPACE" "$POD_NAME" --ignore-not-found >/dev/null
fi

