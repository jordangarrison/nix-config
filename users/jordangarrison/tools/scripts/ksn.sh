#!/usr/bin/env bash
# Switch kubectl namespace in current context

if [ -z "$1" ]; then
  echo "Usage: ksn <namespace>"
  exit 1
fi

kubectl get namespace "$1" >/dev/null || exit $?
kubectl config set-context "$(kubectl config current-context)" --namespace="$1"
echo "Namespace: $1"
