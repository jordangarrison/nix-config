#!/usr/bin/env bash
set -euo pipefail

# This script is used to authenticate to AWS using Okta and the AWS CLI.
# It also utilizes 1password to retrieve the Okta password.
export AWS_PROFILE="${1:-"flostag"}"
export AWS_KUBE_CLUSTER="${2:-""}"

okta-aws() {
  OKTA_PROFILE="$1" withokta "aws --profile $1" "${@:2}"
}

# Get the Okta password from 1password
if env | grep -q OP_SESSION && false; then
  eval $(op signin)
fi

# login to aws using okta
okta-aws "${AWS_PROFILE}" sts get-caller-identity

# Get the kubeconfig for the cluster if it was passed in
if [ -n "${AWS_KUBE_CLUSTER}" ]; then
  aws eks --region us-west-2 update-kubeconfig --name "${AWS_KUBE_CLUSTER}"
fi
