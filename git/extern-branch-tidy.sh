#!/bin/bash

SCRIPT_PATH=$(dirname "${BASH_SOURCE[0]}")/branch-tidy.sh
osascript -e "tell application \"Terminal\" to do script \"$SCRIPT_PATH $*; sleep 3; exit;\""
