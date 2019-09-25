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

function echo_error()     { echo -e "\\033[0;31m[ERROR] $*\\033[0m"; }
function echo_warn()      { echo -e "\\033[0;33m[WARN] $*\\033[0m"; }
function echo_soft_warn() { echo -e "\\033[0;33m$*\\033[0m"; }
function echo_success()   { echo -e "\\033[0;32m$*\\033[0m"; }
function echo_info()      { echo -e "$*\\033[0m"; }

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
        echo_warn "You are on this branch so it cannot be deleted."
        if ask "Checkout $release_branch and try again?"; then
            if ! git checkout -q "$release_branch"; then
                echo_error "Could not checkout $RELEASE_BRANCH. $branch_name will not be deleted"
            fi
        fi
    fi

    # TODO: delete remote tracking branch if it exists too
    if git branch -q -D "$branch_name"; then
        echo_success "Deleted $branch_name"
    else
        echo_error "Failed to delete $branch_name"
    fi
}

function sanity_check_directory() {
    if ! [ -d "$GIT_DIR/.git" ]; then
        echo_error "Directory is not a git repository"
        return 1
    fi

    if ! [ -x "$(command -v git)" ]; then
        echo_error "Missing git command. To install run: brew install git"
        return 1
    fi
}

function fetch_branches() {
    echo_info "Fetching $RELEASE_BRANCH (and pruning)..."
    if ! git fetch -q origin $RELEASE_BRANCH:$RELEASE_BRANCH --update-head-ok --prune; then
        echo_error "Could not fetch $RELEASE_BRANCH"
        return 1
    fi
}

function scan_branches_for_deletion() {
    RELEASE_BRANCH_COMMIT=$(git rev-parse master)

    # pull all local branches (exclude master)
    ALL_BRANCHES=($(git for-each-ref refs/heads/ "--format=%(refname:short)" --no-contains="$RELEASE_BRANCH"))

    MERGED_BRANCHES=()

    # TODO: detect branches that are many many commits behind master
    # TODO: detect branches that have no remote branch (not tracked)

    # thank you: https://github.com/not-an-aardvark/git-delete-squashed#sh
    for refname in "${ALL_BRANCHES[@]}"; do :
        # list out merged branches from master, but only look at the curent branch
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
        echo_success "No merged/squashed branches found. Well done!"
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
}

function main() {
    local GIT_DIR=$(pwd)
    local OPTIND opt
    RELEASE_BRANCH="master"

    while getopts ":hC:b:" opt; do
        case "${opt}" in
            C)
                GIT_DIR="$OPTARG"
            ;;
            b)
                RELEASE_BRANCH="$OPTARG"
            ;;
            h)
                echo -e "Usage:\nbranch-tidy.sh [-C path/to/repo] [-b master]" && exit 0
            ;;
            \?)
                echo "Invalid Option: -$OPTARG" 1>&2
                exit 1
            ;;
        esac
    done

    cd "$GIT_DIR"
    echo_soft_warn "Running in directory: $PWD"
    echo_soft_warn "Comparing against branch: $RELEASE_BRANCH"

    sanity_check_directory || exit 1

    INITIAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    fetch_branches || :

    scan_branches_for_deletion || exit 1

    echo_success "Done!"
}; main "$@"
