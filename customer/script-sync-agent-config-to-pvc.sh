#!/usr/bin/env bash
set -euo pipefail

# Copy a local directory into a PVC using a temporary helper pod.
#
# Usage:
#   ./customer/script-sync-agent-config-to-pvc.sh <namespace> <pvcName> <sourceDir>
#
# Example:
#   ./customer/script-sync-agent-config-to-pvc.sh it-self-service-agent it-self-service-agent-agent-service-config ./agent-service/config

die() { echo "ERROR: $*" >&2; exit 1; }

NAMESPACE="${1:-}"
PVC_NAME="${2:-}"
SRC_DIR="${3:-}"

[[ -n "$NAMESPACE" ]] || die "Usage: $0 <namespace> <pvcName> <sourceDir>"
[[ -n "$PVC_NAME" ]] || die "Usage: $0 <namespace> <pvcName> <sourceDir>"
[[ -n "$SRC_DIR" ]] || die "Usage: $0 <namespace> <pvcName> <sourceDir>"
[[ -d "$SRC_DIR" ]] || die "sourceDir not found: $SRC_DIR"

command -v oc >/dev/null 2>&1 || die "oc is required"

POD_NAME="ssa-config-sync"
MOUNT_PATH="/mnt/config"

oc get pvc "$PVC_NAME" -n "$NAMESPACE" >/dev/null

cat <<YAML | oc apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
spec:
  restartPolicy: Never
  containers:
    - name: sync
      image: registry.access.redhat.com/ubi9/ubi:latest
      command: ["bash","-lc","sleep 3600"]
      volumeMounts:
        - name: cfg
          mountPath: ${MOUNT_PATH}
  volumes:
    - name: cfg
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
YAML

oc wait -n "$NAMESPACE" --for=condition=Ready "pod/${POD_NAME}" --timeout=120s

# Replace contents
oc exec -n "$NAMESPACE" "${POD_NAME}" -- bash -lc "rm -rf '${MOUNT_PATH:?}'/* '${MOUNT_PATH:?}'/.[!.]* '${MOUNT_PATH:?}'/..?* 2>/dev/null || true"
tar -C "$SRC_DIR" -cf - . | oc exec -i -n "$NAMESPACE" "${POD_NAME}" -- tar -C "$MOUNT_PATH" -xf -

oc delete pod -n "$NAMESPACE" "$POD_NAME" --ignore-not-found >/dev/null

