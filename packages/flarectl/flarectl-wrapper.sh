#!/usr/bin/env bash

set -euo pipefail

SECRETS_FILE="/var/lib/acme-secrets/cloudflare-env"

# Source the ACME secrets file if no CF_API_TOKEN is already set
if [ -z "${CF_API_TOKEN:-}" ] && [ -r "$SECRETS_FILE" ]; then
  # The ACME secrets file may use CLOUDFLARE_DNS_API_TOKEN or CF_DNS_API_TOKEN
  # shellcheck source=/dev/null
  source "$SECRETS_FILE"
  export CF_API_TOKEN="${CF_API_TOKEN:-${CLOUDFLARE_DNS_API_TOKEN:-${CF_DNS_API_TOKEN:-}}}"
fi

if [ -z "${CF_API_TOKEN:-}" ]; then
  echo "Error: No Cloudflare API token found." >&2
  echo "Set CF_API_TOKEN or ensure $SECRETS_FILE is readable." >&2
  exit 1
fi

export CF_API_TOKEN
exec flarectl "$@"
