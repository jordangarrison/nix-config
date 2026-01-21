#!/usr/bin/env bash

# Credit ThePrimeagen dotfiles https://github.com/ThePrimeagen/.dotfiles/blob/master/bin/.local/bin/tmux-cht.sh
selected=`cat ~/.tmux-cht-languages ~/.tmux-cht-commands | fzf`
if [[ -z $selected ]]; then
    exit 0
fi

read -p "Enter Query: " query

if grep -qs "$selected" ~/.tmux-cht-languages; then
    query=`echo $query | tr ' ' '+'`
    tmux neww bash -c "echo \"curl cht.sh/$selected/$query/\" & curl cht.sh/$selected/$query | less & while [ : ]; do sleep 1; done"
else
    tmux neww bash -c "curl -s cht.sh/$selected~$query | less"
fi
