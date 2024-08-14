#!/usr/bin/env bash

# wrapper script which deletes borked namespaces from EKS because it's dumb
# usage: borked-ns.sh <namespace>
# example: borked-ns.sh preview-blah-123

function list-borked-ns-objects {
  local NAMESPACE=${1:?Please provide a namespace}
  kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n 1 kubectl get --show-kind --ignore-not-found -n ${NAMESPACE}
}

function delete-borked-ns {
  local NAMESPACE=${1:?Please provide a namespace}
  kubectl get namespace "${NAMESPACE}" -o json \
    | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
    | kubectl replace --raw /api/v1/namespaces/${NAMESPACE}/finalize -f -
}

function _borked-ns {
  # list available namespaces in the EKS cluster without colors in TERMINATING state
  local AVAILABLE_NAMESPACES="$(kubectl get ns --field-selector status.phase=Terminating -o jsonpath='{.items[*].metadata.name}')"

  # if no namespace is provided, list available namespaces
  COMPREPLY=()

  if [ "$COMP_CWORD" -eq 1 ]; then
    local CURRENT_WORD=${COMP_WORDS[COMP_CWORD]}
    COMPREPLY=($(compgen -W "$AVAILABLE_NAMESPACES" -- $CURRENT_WORD))
  fi
}

complete -F _borked-ns delete-borked-ns
complete -F _borked-ns list-borked-ns-objects