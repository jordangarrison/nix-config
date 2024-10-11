#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
	echo "Usage: $0 <local port> <remote host> <remote port>"
	exit 1
fi

LOCAL_PORT=$1
REMOTE_HOST=$2
REMOTE_PORT=$3
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
USERNAME=${USERNAME:0:50}
POD_NAME="socat-$USERNAME"

cleanup() {
	echo "Cleaning up..."
	kubectl delete "pod/$POD_NAME" -n default --ignore-not-found=true
}

trap cleanup EXIT

# Check if the socat pod already exists
POD_STATUS=$(kubectl get pod/$POD_NAME -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

if [[ "$POD_STATUS" != "Running" ]]; then
	echo "Starting socat pod with name: $POD_NAME..."
	kubectl run "$POD_NAME" -n default --image=alpine/socat --restart=Never --command -- \
		socat TCP-LISTEN:12345,fork TCP:"$REMOTE_HOST":"$REMOTE_PORT"
else
	echo "Using existing socat pod: $POD_NAME..."
fi

echo "Waiting for socat pod to be ready..."
kubectl wait --for=condition=Ready pod/$POD_NAME -n default --timeout=60s

echo "Port forwarding from localhost:$LOCAL_PORT to $REMOTE_HOST:$REMOTE_PORT on pod/$POD_NAME..."
echo "Press Ctrl+C to stop and clean up"
kubectl port-forward pod/$POD_NAME "$LOCAL_PORT:12345" -n default
