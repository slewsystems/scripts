#!/usr/bin/env bash

# ---------------------------
# Author: Brandon Patram
# Date: 2018-06-19
#
# Description: Pull a branch down without losing your current state
# Will stash your current changes and re-apply them after pulling
# down the target branch (or master if not defined)
#
# Usage: inplace-pull.sh [-C path to repo] [-b branch to pull=master]
# Examples:
# ../inplace-pull.sh -b master
# inplace-pull.sh -b develop -C path/to-repo
# inplace-pull.sh -C path/to-repo
# ---------------------------

STASH_MESSAGE=$(uuidgen)
SILENCE=false
TARGET_BRANCH=""
GIT_DIR=$(pwd)

function echo_error() { echo -e "\\033[0;31m[ERROR] $*\\033[0m"; }
function echo_warn() { echo -e "\\033[0;33m[WARN] $*\\033[0m"; }
function echo_soft_warn() { if [ "$SILENCE" = false ]; then echo -e "\\033[0;33m$*\\033[0m"; fi; }
function echo_success() { if [ "$SILENCE" = false ]; then echo -e "\\033[0;32m$*\\033[0m"; fi; }
function echo_info() { if [ "$SILENCE" = false ]; then echo -e "$*\\033[0m"; fi; }

while getopts ":hC:b:q" opt; do
    case "${opt}" in
    C)
        GIT_DIR="$OPTARG"
        ;;
    q)
        SILENCE=true
        ;;
    b)
        TARGET_BRANCH="$OPTARG"
        ;;
    h)
        echo -e "Usage:\ninplace-pull.sh [-C path/to/repo] [-b master]" && exit 0
        ;;
    \?)
        echo "Invalid Option: -$OPTARG" 1>&2
        exit 1
        ;;
    esac
done

if cd "$GIT_DIR"; then
    echo_soft_warn "Running in directory: $PWD"
fi

if ! [ -d "$GIT_DIR/.git" ]; then
    echo_error "Directory is not a git repository"
    exit 1
fi

if ! [ -x "$(command -v git)" ]; then
    echo_error "Missing git command. To install run: brew install git"
    exit 1
fi

if [[ -z "$TARGET_BRANCH" ]]; then
    TARGET_BRANCH="master"
    echo_warn "No target branch specified, using $TARGET_BRANCH instead"
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo_info "Stashing current changes: $STASH_MESSAGE..."
git stash push -q -u -m "$STASH_MESSAGE"
# find stash number from message
# since we use a uuid lets assume we will only ever get one match
STASH_ID=$(git stash list -n 1 --grep="$STASH_MESSAGE" | cut -f 1 -d ':')
git checkout -q "$TARGET_BRANCH"

echo_info "Pulling $TARGET_BRANCH..."
git pull -q origin "$TARGET_BRANCH"
git fetch --prune --prune-tags -q

echo_info "Restoring original state of $CURRENT_BRANCH..."
git checkout -q "$CURRENT_BRANCH"

# if a stash was made/found, pop it
# its possible a stash was not created if there was nothing to stash
if [ -n "$STASH_ID" ]; then
    git stash pop -q "$STASH_ID"
fi

echo_success "Done!"
