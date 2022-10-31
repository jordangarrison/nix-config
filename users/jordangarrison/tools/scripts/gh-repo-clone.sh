#!/usr/bin/env bash

ORG_NAME=${1:-flocasts}

pushd ~/dev/
gh repo list ${ORG_NAME} --limit 1000 | while read -r repo _; do
  gh repo clone "$repo" -- -q 2>/dev/null || (
    cd "$(basename $repo)"
    # Handle case where local checkout is on a non-main/master branch
    # - ignore checkout errors because some repos may have zero commits, 
    # so no main or master
    git checkout -q main 2>/dev/null || true
    git checkout -q master 2>/dev/null || true
    git pull -q
  )
done
popd
