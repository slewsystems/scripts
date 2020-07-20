#!/usr/bin/env bash
set -e

# ---------------------------
# Author: Brandon Patram
# Date: 2018-08-13
#
# Description: Find local branches that are merged
# or have been squashed into a single merge commit
# into master then prompt to delete them or all of them
#
# Usage: branch-tidy.sh [-C $(pwd)] [-b master] [-r origin] [-v] [-y]
# Options:
# -C specify path to local repo. When omitted the current directory is used
# -b specify the primary branch to compare against. When omitted 'master' is used
# -r specify the primary remote to compare again. When omitted 'origin' is used
# -v enable verbose output, primarily useful for debugging this script itself
# -y auto response 'yes' to prompts
# ---------------------------

function echo_error() { echo -e "\\033[0;31m[ERROR] $*\\033[0m"; }
function echo_warn() { echo -e "\\033[0;33m[WARN] $*\\033[0m"; }
function echo_soft_warn() { echo -e "\\033[0;33m$*\\033[0m"; }
function echo_success() { echo -e "\\033[0;32m$*\\033[0m"; }
function echo_info() { echo -e "$*\\033[0m"; }

# print_branch_list_item [branch status] [branch name]
# print_branch_list_item "ignored" [branch_name]
# print_branch_list_item "squashed" [branch_name]
# print_branch_list_item "merged" [branch_name]
# print_branch_list_item "not merged" [branch_name]
function print_branch_list_item() {
    local COLOR="\\033[0m" # no color
    local BRANCH_STATUS="$1"
    local BRANCH_NAME="$2"

    case "$BRANCH_STATUS" in
    "squashed" | "merged")
        COLOR="\\033[0;31m" # red
        ;;
    "not merged")
        COLOR="\\033[0;34m" # blue
        ;;
    "ignored")
        COLOR="\\033[0;32m" # green
        ;;
    esac

    printf "${COLOR}%10s\\033[0m\\t%s \\n" "$BRANCH_STATUS" "$BRANCH_NAME"
}

# Look for an element in a list (thank you: https://stackoverflow.com/a/8063398/5286136)
# list_contains $list "something"
function list_contains() { [[ $1 =~ (^|[[:space:]])$2($|[[:space:]]) ]]; }

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

function prompt_destroy_branch() {
    local branch_name
    local default_response
    branch_name=$1
    default_response=${2:n}

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

# Check to make sure required dependencies are available
function ensure_requirements() {
    if ! [ -x "$(command -v git)" ]; then
        echo_error "Missing git command. To install run: brew install git"
        return 1
    fi
}

function ensure_git_repo() {
    if ! [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]; then
        echo_error "Directory is not a git repo"
        return 1
    fi
}

function fetch_branches() {
    echo_info "Fetching $RELEASE_BRANCH (and pruning)..."
    if ! git fetch -q "$PRIMARY_REMOTE" "$RELEASE_BRANCH" --update-head-ok --prune; then
        echo_error "Could not fetch $RELEASE_BRANCH"
        return 1
    fi
}

# Check if the branch has been merged into the RELEASE_BRANCH via merge commit
# Usage: branch_merged "branch_name"
function branch_merged() {
    local refname=$1

    # list out merged branches from RELEASE_BRANCH, but only look at the curent branch
    # and ignore RELEASE_BRANCH itself. pretty much: if this returns nothing then no
    # merged branches (this branch) are merged. if there is a return value then
    # thats means this branch is merged via a merge commit.
    merged_branch=$(git branch --merged="$RELEASE_BRANCH" --contains="$refname" --no-contains="$RELEASE_BRANCH")

    # if the output is empty, then the branch is merged
    if [ -n "$merged_branch" ]; then
        return 0
    else
        return 1
    fi
}

function scan_branches_for_deletion() {
    local RELEASE_BRANCH_COMMIT ALL_BRANCHES

    RELEASE_BRANCH_COMMIT=$(git rev-parse "$RELEASE_BRANCH")
    # pull all local branches (exclude RELEASE_BRANCH)
    ALL_BRANCHES=($(git for-each-ref refs/heads/ "--format=%(refname:short)" --no-contains="$RELEASE_BRANCH"))

    local MERGED_BRANCHES=()
    local IGNORED_BRANCHES=("master" "$RELEASE_BRANCH")

    # TODO: detect branches that are many many commits behind master
    # TODO: detect branches that have no remote branch (not tracked)

    # thank you: https://github.com/not-an-aardvark/git-delete-squashed#sh
    for refname in "${ALL_BRANCHES[@]}"; do
        # check if the branch is a whitelisted one. if so, then skip it
        if list_contains "${IGNORED_BRANCHES[*]}" "$refname"; then
            print_branch_list_item "ignored" "$refname"
            continue
        fi

        # lets check if the branch is merged into latest master.
        # if not then lets check if the branch has been squashed into master
        if branch_merged "$refname"; then
            print_branch_list_item "merged" "$refname"
            MERGED_BRANCHES+=("$refname")
        else
            # find commit on master that this branch branched from or the common ancestor
            merge_base=$(git merge-base "$RELEASE_BRANCH_COMMIT" "$refname")
            # get tree hash ref of branch
            tree=$(git rev-parse "$refname^{tree}")
            # create a temporary dangling commit... we will use this to compare to commits in master
            commit_tree=$(git commit-tree "$tree" -p "$merge_base" -m _)
            # does this commit exist in commit history?
            cherry_commit=$(git cherry "$RELEASE_BRANCH" "$commit_tree")

            if [[ $cherry_commit == "-"* ]]; then
                print_branch_list_item "squashed" "$refname"
                MERGED_BRANCHES+=("$refname")
            else
                print_branch_list_item "not merged" "$refname"
            fi
        fi
    done

    if [ ${#MERGED_BRANCHES[@]} -eq 0 ]; then
        echo_success "No merged/squashed branches found. Well done!"
        exit 0
    fi

    if [ "$AUTO_YES" = true ] | ask "Delete all ${#MERGED_BRANCHES[@]} merged/squashed branches?" "N"; then
        for refname in "${MERGED_BRANCHES[@]}"; do
            destroy_branch "$refname"
        done
    else
        for refname in "${MERGED_BRANCHES[@]}"; do
            prompt_destroy_branch "$refname" "N"
        done
    fi
}

function main() {
    local GIT_DIR opt

    GIT_DIR=$(pwd)
    PRIMARY_REMOTE="origin"
    RELEASE_BRANCH="master"
    AUTO_YES=false

    while getopts ":vyhC:b:r:" opt; do
        case "${opt}" in
        C)
            GIT_DIR="$OPTARG"
            ;;
        b)
            RELEASE_BRANCH="$OPTARG"
            ;;
        r)
            PRIMARY_REMOTE="$OPTARG"
            ;;
        h)
            echo -e "Usage:\nbranch-tidy.sh [-C path/to/repo] [-b master]" && exit 0
            ;;
        v)
            set -x
            ;;
        y)
            AUTO_YES=true
            ;;
        \?)
            echo "Invalid Option: -$OPTARG" 1>&2
            exit 1
            ;;
        esac
    done

    cd "$GIT_DIR" || exit 1
    echo_soft_warn "Running in directory: $PWD"

    ensure_requirements || exit 1
    ensure_git_repo || exit 1

    echo_soft_warn "Comparing against branch: $RELEASE_BRANCH"

    INITIAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    fetch_branches || echo_warn "Comparing to outdated repo state!"

    scan_branches_for_deletion || exit 1

    echo_success "Done!"
}
main "$@"
