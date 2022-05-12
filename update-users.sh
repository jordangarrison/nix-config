#!/usr/bin/env bash

# Read in the command line arguments and set the $DRY_RUN flag
while getopts ":d" opt; do
  case $opt in
  d)
    DRY_RUN=true
    shift
    ;;
  \?)
    echo "Invalid option: -$OPTARG" >&2
    exit 1
    ;;
  esac
done

# select the correct config file
SCRIPTPATH="$(
  cd "$(dirname "$0")"
  pwd -P
)"
CONFIG_DIR="$SCRIPTPATH"/users/$USER
echo "$CONFIG_DIR"

# update the config

# copy new file to /etc/nixos unless $DRY_RUN is set
if [ -z "$DRY_RUN" ]; then
  home-manager switch -f "${CONFIG_DIR}/home.nix"
else
  echo "Dry Run"
fi
