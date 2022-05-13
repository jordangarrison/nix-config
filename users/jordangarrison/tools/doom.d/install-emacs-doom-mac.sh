#!/usr/bin/env bash

HOMEBREW="$(which brew)" ; [ -z "$HOMEBREW" ] && echo "No brew binary found, please install Homebrew" && exit 1
GIT_EXEC="$(which git)" ; [ -z "$GIT_EXEC" ] && echo "No git binary found, please install git" && exit 1
EMACS_TAP="d12frosted/emacs-plus"

cat <<EOF
Using the following executables for installation:
  Homebrew:  $HOMEBREW
  Git:       $GIT_EXEC
  Brew Tap:  $EMACS_TAP
EOF

echo "Installing Emacs"
$HOMEBREW tap | grep "$EMACS_TAP"
RETVAL=$?
if [ $RETVAL -ne 0 ]; then
    brew tap d12frosted/emacs-plus
else
    echo "Emacs already Tapped in Homebrew"
fi

echo "Finding emacs app file"
EMACS_APP_FILE="$(find /usr/local -name "Emacs.app")"
echo "Found emacs app file at '$EMACS_APP_FILE'"

[ -z "$EMACS_APP_FILE" ] && echo "No Emacs.app mac application file found" && echo "You may want to consider a different version of emacs"
if [ -f "/Applications/Emacs" ] ; then
    echo "Emacs.app already linked"
else
    osascript -e "tell application \"Finder\" to make alias file to (POSIX file \"$EMACS_APP_FILE\") at POSIX file \"/Applications\""
fi

echo "Installing Doom emacs"
if [ -f "$HOME/.emacs.d/bin/doom" ] ; then
    echo "Doom emacs already installed"
else
    git clone https://github.com/hlissner/doom-emacs "$HOME"/.emacs.d
    "$HOME"/.emacs.d/bin/doom install
    export PATH=$HOME/.emacs.d/bin:$PATH
    echo "Done"
fi

echo "Finished installing doom emacs"
