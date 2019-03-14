#!/bin/bash

# ---------------------------
# Author: Brandon Patram
# Date: 2018-08-06
#
# Description: List all files in glob format
# that have changed in between a specific
# commit and master that match the passed
# regex pattern.
#
# Usage: glob-changed-files.sh [regex_pattern] [to_commit=HEAD] [from_commit=origin/master]

# Examples:
# glob-changed-files.sh "\\.(scss|css)" => list of scss/css files in HEAD commit to master
# glob-changed-files.sh "\\.(js)" "ABCDE" => list of js files in commit ABCDE to master
# glob-changed-files.sh => list of all files in HEAD commit to master
# ---------------------------

function join_by {
    local IFS="$1"
    shift
    echo "$*"
}

MATCH_PATTERN="${1}"
COMPARE_FROM_COMMIT="${3}"
COMPARE_TO_COMMIT="${2-HEAD}"

if [ -z "$COMPARE_FROM_COMMIT" ]; then
    # Get the commit of master. This will be latest master since circle pulls down
    # a fresh clone of the repo at run time.
    LOCAL_MASTER=$(git show-ref --heads -s "master")
    # Then get the commit where this branch branches off of master from
    # We will use that commit when comparing what files have changed on this branch
    COMPARE_FROM_COMMIT=$(git merge-base "$LOCAL_MASTER" "$COMPARE_TO_COMMIT")
fi

# get the list of files changed between FROM and TO
# now we can simply grep to only pull out certain files
FILES=($(git diff --name-only $COMPARE_FROM_COMMIT.."$COMPARE_TO_COMMIT" | grep -E "$MATCH_PATTERN"))

if [ "${#FILES[@]}" -gt 1 ]; then
    GLOB=$(join_by "," "${FILES[@]}")
    # wrap results in curly brackets when globing more than one file
    echo "{$GLOB}"
elif [ "${#FILES[@]}" -eq 0 ]; then
    # when there is no results return "nothing"

    # when this is used for linters then it will attempt to only lint the literal
    # file of 'nothing' (which doesn't exist) and passes. otherwise, if we were
    # to return an empty string then most linters will ignore it and scan ALL
    # files. which is no bueno
    echo "nothing"
else
    # just return a single file name if there is a single file
    # if we were to return a single result in curly brackets it doesn't work
    # i'm not sure why, but i think its just a violation of the globbing format
    echo "${FILES[@]}"
fi
