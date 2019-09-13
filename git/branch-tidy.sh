#!/bin/bash
set -e

# ---------------------------
# Author: Brandon Patram
# Date: 2018-08-13
#
# Description: Find local branches that are merged
# or have been squashed into a single merge commit
# into master then prompt to delete them or all of them
#
# Usage: branch-tidy.sh [path to repo=$(pwd)]
# Examples:
# ../branch-tidy.sh
# branch-tidy.sh path/to-repo
# yes y | branch-tidy.sh path/to-repo
# ---------------------------

Y="\\033[0;33m"
G="\\033[0;32m"
R="\\033[0;31m"
NC="\\033[0m"
# BOLD="\\033[1m"

CWD=$(pwd)
GIT_DIR=${1:-$CWD}

function ask() {
    # https://djm.me/ask
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
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac
    done
}

function prompt_destroy_branch() {
    branch_name=$1
    default_response=${2:N}

    if ask "Delete branch ${branch_name}?" "${default_response}"; then
        destroy_branch "$branch_name"
    fi
}

function destroy_branch() {
    branch_name=$1
    current_branch_name=$INITIAL_BRANCH
    release_branch=$RELEASE_BRANCH

    # we cannot delete the branch we are currently on
    # so lets check if we are on that branch, if so
    # attempt to checkout master and then try to delete
    if [ "$current_branch_name" == "$branch_name" ]; then
        echo -e "${Y}WARN: You are on this branch so it cannot be deleted.${NC}"
        if ask "Checkout $release_branch and try again?"; then
            if ! git checkout -q "$release_branch"; then
                echo -e "${R}ERROR: Could not checkout $RELEASE_BRANCH. $branch_name will not be deleted${NC}"
            fi
        fi
    fi

    # TODO: delete remote tracking branch if it exists too
    if git branch -q -D "$branch_name"; then
        echo -e "${G}Deleted $branch_name${NC}"
    else
        echo -e "${R}ERROR: Failed to delete $branch_name${NC}"
    fi
}

if [ -d "$GIT_DIR/.git" ]; then
    cd "$GIT_DIR" || exit 1
    echo -e "${Y}Running in directory: $(pwd)${NC}"
else
    echo -e "${R}ERROR: Directory is not a git repository${NC}"
    exit 1
fi

if ! [ -x "$(command -v git)" ]; then
    echo -e "${R}ERROR: Missing git command. To install run: ${NC}brew install git${NC}"
    exit 1
fi

RELEASE_BRANCH=master
INITIAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo -e "${Y}Fetching $RELEASE_BRANCH (and pruning)...${NC}"
if ! git fetch --quiet origin $RELEASE_BRANCH:$RELEASE_BRANCH --update-head-ok --prune; then
    echo -e "${R}ERROR: Could not fetch $RELEASE_BRANCH${NC}"
fi

RELEASE_BRANCH_COMMIT=$(git rev-parse master)

# pull all local branches (exclude master)
ALL_BRANCHES=($(git for-each-ref refs/heads/ "--format=%(refname:short)" --no-contains="$RELEASE_BRANCH"))

MERGED_BRANCHES=()

# TODO: detect branches that are many many commits behind master
# TODO: detect branches that have no remote branch (not tracked)

# thank you: https://github.com/not-an-aardvark/git-delete-squashed#sh
for refname in "${ALL_BRANCHES[@]}"; do :
    # list out merged branches from master, but only look at the current branch
    # and ignore master itself. pretty much: if this returns nothing then no
    # merged branch (this branch) is merged. if there is a return value then
    # thats means this branch is merged!
    merged_branch=$(git branch --merged="$RELEASE_BRANCH" --contains="$refname" --no-contains="$RELEASE_BRANCH")

    # lets check if the branch is merged into latest master.
    # if not then lets check if the branch has been squashed into master
    if ! [ -z "$merged_branch" ]; then
        printf "${G}%10s${NC}\\t%s \\n" "merged" "$refname"
        MERGED_BRANCHES+=("$refname")
    else
        # find commit on master that this branch branched from or the common ancestor
        merge_base=$(git merge-base "$RELEASE_BRANCH_COMMIT" "$refname")
        # get tree hash ref of branch
        tree=$(git rev-parse "$refname^{tree}")
        # create a temporary dangling commit... we will use this to compare to commits in master
        commit_tree=$(git commit-tree "$tree" -p "$merge_base" -m _)
        # does this commit exist in commit history?
        cherry_commit=$(git cherry master "$commit_tree")

        if [[ $cherry_commit == "-"* ]]; then
            printf "${G}%10s${NC}\\t%s \\n" "squashed" "$refname"
            MERGED_BRANCHES+=("$refname")
        else
            printf "${R}%10s${NC}\\t%s \\n" "not merged" "$refname"
        fi
    fi
done

if [ ${#MERGED_BRANCHES[@]} -eq 0 ]; then
    echo -e "${G}No merged/squashed branches found. Well done!${NC}"
    exit 0
fi

if ask "Delete all ${#MERGED_BRANCHES[@]} merged/squashed branches?" "N"; then
    for refname in "${MERGED_BRANCHES[@]}"; do :
        destroy_branch "$refname"
    done
else
    for refname in "${MERGED_BRANCHES[@]}"; do :
        prompt_destroy_branch "$refname" "N"
    done
fi

echo -e "${G}Done!${NC}"
