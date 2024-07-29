#!/usr/bin/env bash

# wrapper script around code which opens a project in the ~/dev/ directory in VSCode
# usage: vscode.sh <project-name>
# example: vscode.sh tools

function vscode {
  local PROJECT=${1:?Please provide a project name}
  code ~/dev/$PROJECT
}

function _vscode {
  # list available projects in the ~/dev directory without colors
  local AVAILABLE_PROJECTS="$(\ls ~/dev)"

  # if no project name is provided, list available projects
  COMPREPLY=()

  if [ "$COMP_CWORD" -eq 1 ]; then
    local CURRENT_WORD=${COMP_WORDS[COMP_CWORD]}
    COMPREPLY=($(compgen -W "$AVAILABLE_PROJECTS" -- $CURRENT_WORD))
  fi
}

complete -F _vscode vscode
