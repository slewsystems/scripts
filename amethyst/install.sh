#!/usr/bin/env bash

# ---------------------------
# Author: Brandon Patram
# Date: 2023-04-14
#
# Description: Copies custom Amethyst layouts in the current directory
# into the Amethyst layout directory and restarts Amethyst
#
# Usage: install.sh
# ---------------------------

AMETHYST_LAYOUT_PATH="$HOME/Library/Application Support/Amethyst/Layouts"

function echo_error() { echo -e "\\033[0;31m[ERROR] $*\\033[0m"; }
function echo_warn() { echo -e "\\033[0;33m[WARN] $*\\033[0m"; }
function echo_soft_warn() { echo -e "\\033[0;33m$*\\033[0m"; }
function echo_success() { echo -e "\\033[0;32m$*\\033[0m"; }
function echo_info() { echo -e "$*\\033[0m"; }
function ask() {
  # https://gist.github.com/davejamesmiller/1965569
  local prompt default reply

  while true; do
    if [ "${2:-}" = "Y" ]; then
      prompt="Y/n"
      default=Y
    elif [ "${2:-}" = "N" ]; then
      prompt="y/N"
      default=N
    else
      prompt="y/n"
      default=
    fi

    echo -n "$1 [$prompt] "
    read -r reply </dev/tty

    if [ -z "$reply" ]; then
      reply=$default
    fi

    case "$reply" in
    Y* | y*) return 0 ;;
    N* | n*) return 1 ;;
    esac
  done
}

if [ ! -d "$AMETHYST_LAYOUT_PATH" ]; then
  echo_info "Checking for $AMETHYST_LAYOUT_PATH"
  echo_error "ERROR: Missing Amethyst layout directory"
  echo_info "Is Amethyst installed? To install: brew install amethyst"
  exit 1
fi

echo_soft_warn "Looking for layout files in directory: $PWD"

for LAYOUT_FILE in *.js; do
  DEST_FILE="$AMETHYST_LAYOUT_PATH/$(basename "$LAYOUT_FILE")"

  if [ -f "$DEST_FILE" ]; then
    if ! ask "Overwrite existing layout?"; then
      continue
    fi
  fi

  cp -f "$LAYOUT_FILE" "$DEST_FILE"
done

echo_success "Done!"
