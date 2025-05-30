#!/usr/bin/env bash

set -euo pipefail

# myip.sh - Script to fetch and display public IP address and its details
# Created: $(date)

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print section headers
print_header() {
    echo -e "\n${BOLD}${BLUE}$1${NC}"
    echo -e "${CYAN}$(printf '=%.0s' {1..50})${NC}"
}

# Function to print key-value pairs
print_info() {
    printf "${BOLD}${GREEN}%-15s${NC} : ${YELLOW}%s${NC}\n" "$1" "$2"
}

# Function to handle errors
handle_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Check for dependencies
for dep in curl jq; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        handle_error "Required dependency '$dep' is not installed."
    fi
done

# Parse arguments
RAW_OUTPUT=false
for arg in "$@"; do
    case "$arg" in
    --json | --raw)
        RAW_OUTPUT=true
        ;;
    -h | --help)
        echo "Usage: $0 [--json|--raw]"
        exit 0
        ;;
    *)
        handle_error "Unknown argument: $arg"
        ;;
    esac
done

# Fetch public IP
IP=$(curl -s https://api.ipify.org)
if [ -z "$IP" ]; then
    handle_error "Could not retrieve your public IP address. Check your internet connection."
fi

# Fetch IP details
IP_INFO=$(curl -s "https://ipinfo.io/$IP/json")
if [ -z "$IP_INFO" ] || echo "$IP_INFO" | jq -e '.error? // empty' >/dev/null; then
    handle_error "Could not retrieve IP details. Service might be unavailable."
fi

if [ "$RAW_OUTPUT" = true ]; then
    echo "$IP_INFO" | jq
    exit 0
fi

# Only print the following if not in JSON/raw mode

# Print welcome message
echo -e "\n${BOLD}${PURPLE}========== PUBLIC IP INFORMATION TOOL ==========${NC}\n"
print_header "FETCHING IP ADDRESS"
echo -e "${CYAN}Retrieving your public IP address...${NC}"
print_info "Public IP" "$IP"

print_header "FETCHING IP DETAILS"
echo -e "${CYAN}Retrieving details for IP address: $IP${NC}\n"

# Extract and display information
CITY=$(echo "$IP_INFO" | jq -r '.city // "Unknown"')
REGION=$(echo "$IP_INFO" | jq -r '.region // "Unknown"')
COUNTRY=$(echo "$IP_INFO" | jq -r '.country // "Unknown"')
LOCATION=$(echo "$IP_INFO" | jq -r '.loc // "Unknown"')
ORG=$(echo "$IP_INFO" | jq -r '.org // "Unknown"')
POSTAL=$(echo "$IP_INFO" | jq -r '.postal // "Unknown"')
TIMEZONE=$(echo "$IP_INFO" | jq -r '.timezone // "Unknown"')

# Display information
print_info "City" "$CITY"
print_info "Region" "$REGION"
print_info "Country" "$COUNTRY"
print_info "Postal Code" "$POSTAL"
print_info "Coordinates" "$LOCATION"
print_info "ISP/Org" "$ORG"
print_info "Timezone" "$TIMEZONE"

# Get map URL (Google Maps)
if [ "$LOCATION" != "Unknown" ]; then
    MAP_URL="https://www.google.com/maps?q=$LOCATION"
    echo -e "\n${CYAN}Map Location: ${BLUE}$MAP_URL${NC}"
fi

echo -e "\n${BOLD}${PURPLE}============= END OF REPORT =============${NC}\n"
