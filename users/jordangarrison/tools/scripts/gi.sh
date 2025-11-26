#!/usr/bin/env bash
# Fetch gitignore templates from gitignore.io

if [ -z "$1" ]; then
  echo "Usage: gi <template>"
  echo "Example: gi node,macos"
  exit 1
fi

curl -sLw "\n" "https://www.gitignore.io/api/$1"
