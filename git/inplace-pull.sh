#!/bin/bash

# ---------------------------
# Author: Brandon Patram
# Date: 2018-06-19
#
# Description: Pull a branch down without losing your current state
# Will stash your current changes and re-apply them after pulling
# down the target branch (or master if not defined)
#
# Usage: inplace-pull.sh [path to repo] [branch to pull=master]
# Examples:
# ../inplace-pull.sh master
# inplace-pull.sh develop path/to-repo
# inplace-pull.sh path/to-repo
# ---------------------------

Y="\\033[0;33m"
G="\\033[0;32m"
R="\\033[0;31m"
NC="\\033[0m"
# BOLD="\\033[1m"

CWD=$(pwd)
STASH_MESSAGE=$(uuidgen)
RELEASE_BRANCH=master
TARGET_BRANCH=${1:-$RELEASE_BRANCH}
GIT_DIR=${2:-$CWD}

cd "$GIT_DIR"
echo -e "${Y}Running in directory: $(pwd)${NC}"

if ! [ -d "$GIT_DIR/.git" ]; then
    echo -e "${R}ERROR: Directory is not a git repository${NC}"
    exit 1
fi

if [[ -z "$2" ]]; then
    echo -e "${Y}WARN: No target branch specified, using $TARGET_BRANCH instead${NC}"
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo -e "${Y}Stashing current changes: $STASH_MESSAGE...${NC}"
git stash push -q -u -m "$STASH_MESSAGE"
# find stash number from message
# since we use a uuid lets assume we will only ever get one match
STASH_ID=$(git stash list -n 1 --grep="$STASH_MESSAGE" | cut -f 1 -d ':')
git checkout -q "$TARGET_BRANCH"

echo -e "${Y}Pulling $TARGET_BRANCH...${NC}"
git pull -q origin "$TARGET_BRANCH"
git fetch --prune --prune-tags -q

echo -e "${Y}Restoring original state of $CURRENT_BRANCH...${NC}"
git checkout -q "$CURRENT_BRANCH"

# if a stash was made/found, pop it
# its possible a stash was not created if there was nothing to stash
if ! [[ -z "$STASH_ID" ]]; then
    git stash pop -q "$STASH_ID"
fi

echo -e "${G}Done!${NC}"
