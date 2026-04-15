#!/usr/bin/env bash
set -e

# ---------------------------
# Author: Brandon Patram
# Date: 2026-04-15
#
# Description: Downloads and installs a historical version of Chromium.
#
# Usage: install_chromium.sh [install|search] --version <version> --platform <platform>
# Options:
#  --app:       What to install (chromium or chromium-cef sample app)
#  --version:   Full or partial version of Chromium to search or install (e.g., 130.0.6723.116 or 130.0)
#  --platform:  Platform of the Chromium build (mac-arm64, mac-x64, etc.)
# ---------------------------

function echo_error() { echo -e "\\033[0;31m[ERROR] $*\\033[0m"; }
function echo_warn() { echo -e "\\033[0;33m[WARN] $*\\033[0m"; }
function echo_soft_warn() { echo -e "\\033[0;33m$*\\033[0m"; }
function echo_success() { echo -e "\\033[0;32m$*\\033[0m"; }
function echo_info() { echo -e "$*\\033[0m"; }
function is_command_found() {
  local COMMAND="$1"
  command -v "$COMMAND" >/dev/null 2>/dev/null
}

CHROMIUM_VERSION_API_JSON="https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json"
CHROMIUM_CEF_VERSION_API="https://cef-builds.spotifycdn.com"
CHROMIUM_CEF_VERSION_API_JSON="$CHROMIUM_CEF_VERSION_API/index.json"

function check_dependencies {
  if ! is_command_found jq; then
    echo_error "Missing jq command! Install \`brew install jq\` and try again."
    exit 1
  fi
  if ! is_command_found curl; then
    echo_error "Missing curl command!"
    exit 1
  fi
  if ! is_command_found awk; then
    echo_error "Missing awk command!"
    exit 1
  fi
  if ! is_command_found unzip; then
    echo_error "Missing unzip command!"
    exit 1
  fi
}

function install_chromium {
  local VERSION="$1"
  local PLATFORM="$2"

  echo -n "Fetching Chromium app... "
  # newest version are at bottom
  RESOLVED_DATA=$(list_chromium_versions "$VERSION" "$PLATFORM"  | awk 'END {print}')
  RESOLVED_VERSION=$(echo "$RESOLVED_DATA" | awk '{print $1}')
  RESOLVED_URL=$(echo "$RESOLVED_DATA" | awk '{print $2}')

  if [[ -z "$RESOLVED_DATA" || -z "$RESOLVED_VERSION" || -z "$RESOLVED_URL" ]]; then
    echo_error "No matching version found for version prefix '$VERSION' and platform '$PLATFORM'."
    exit 1
  else
    echo_success "Found! (version: $RESOLVED_VERSION, platform: $PLATFORM)"
  fi

  VERSION_SNAKE_CASE=$(echo "$RESOLVED_VERSION" | tr '.' '_')
  DOWNLOAD_DIRECTORY_PATH="$(dirname ${BASH_SOURCE[0]})/downloads"
  DOWNLOAD_FILE_PATH="$DOWNLOAD_DIRECTORY_PATH/chromium_$VERSION_SNAKE_CASE.zip"
  UNZIP_DIRECTORY_PATH="$DOWNLOAD_DIRECTORY_PATH/chromium_$VERSION_SNAKE_CASE"
  PLATFORM_DIRECTORY="$UNZIP_DIRECTORY_PATH/chrome-$PLATFORM"
  APP_PATH="/Applications/Chromium_$VERSION_SNAKE_CASE.app"

  if [[ -d "$APP_PATH" ]]; then
    echo_soft_warn "Chromium version $RESOLVED_VERSION is already installed at $APP_PATH. Skipping installation."
    return
  fi

  if [[ -f "$DOWNLOAD_FILE_PATH" ]]; then
    echo_soft_warn "Already downloaded. Skipping download step."
  else
    echo "Downloading $RESOLVED_URL"
    mkdir -p "$(dirname "$DOWNLOAD_FILE_PATH")"
    echo "$RESOLVED_URL" | xargs curl -L -o "$DOWNLOAD_FILE_PATH"
  fi

  echo -n "Installing Chromium... "
  unzip -qo "$DOWNLOAD_FILE_PATH" -d "$UNZIP_DIRECTORY_PATH"

  # we use -X to avoid copying extended attributes which causes the "damaged app" error when opening the app for the first time
  cp -fXr "$PLATFORM_DIRECTORY/Google Chrome for Testing.app" "$APP_PATH/"

  echo_success "Installed to $APP_PATH"
}

function install_chromium_cef {
  local VERSION="$1"
  local PLATFORM="$2"

  echo -n "Fetching Chromium CEF client app... "
  # newest version are at bottom
  RESOLVED_DATA=$(list_chromium_cef_versions "$VERSION" "$PLATFORM"  | awk 'END {print}')
  RESOLVED_VERSION=$(echo "$RESOLVED_DATA" | awk '{print $1}')
  RESOLVED_URL=$(echo "$RESOLVED_DATA" | awk '{print $2}')

  if [[ -z "$RESOLVED_DATA" || -z "$RESOLVED_VERSION" || -z "$RESOLVED_URL" ]]; then
    echo_error "No matching version found for version prefix '$VERSION' and platform '$PLATFORM'."
    exit 1
  else
    echo_success "Found! (version: $RESOLVED_VERSION, platform: $PLATFORM)"
  fi

  VERSION_SNAKE_CASE=$(echo "$RESOLVED_VERSION" | tr '.' '_')
  DOWNLOAD_DIRECTORY_PATH="$(dirname ${BASH_SOURCE[0]})/downloads"
  DOWNLOAD_FILE_PATH="$DOWNLOAD_DIRECTORY_PATH/chromium_cef_$VERSION_SNAKE_CASE.tar.bz2"
  UNTAR_DIRECTORY_PATH="$DOWNLOAD_DIRECTORY_PATH/chromium_cef_$VERSION_SNAKE_CASE"
  PLATFORM_DIRECTORY="$UNTAR_DIRECTORY_PATH/$(basename ${RESOLVED_URL%.tar.bz2})/Release"
  APP_PATH="/Applications/Chromium_CEF_$VERSION_SNAKE_CASE.app"

  if [[ -d "$APP_PATH" ]]; then
    echo_soft_warn "Chromium CEF client version $RESOLVED_VERSION is already installed at $APP_PATH. Skipping installation."
    return
  fi

  if [[ -f "$DOWNLOAD_FILE_PATH" ]]; then
    echo_soft_warn "Already downloaded. Skipping download step."
  else
    echo "Downloading $RESOLVED_URL"
    mkdir -p "$(dirname "$DOWNLOAD_FILE_PATH")"
    echo "$RESOLVED_URL" | xargs curl -L -o "$DOWNLOAD_FILE_PATH"
  fi

  echo -n "Installing Chromium... "
  echo $PLATFORM_DIRECTORY
  mkdir -p "$UNTAR_DIRECTORY_PATH"
  tar -xjf "$DOWNLOAD_FILE_PATH" -C "$UNTAR_DIRECTORY_PATH"

  # we use -X to avoid copying extended attributes which causes the "damaged app" error when opening the app for the first time
  cp -fXr "$PLATFORM_DIRECTORY/cefclient.app" "$APP_PATH/"

  echo_success "Installed to $APP_PATH"
}

function list_chromium_versions {
  local VERSION="$1"
  local PLATFORM="$2"

  curl -sL "$CHROMIUM_VERSION_API_JSON" \
    | jq -r \
      --arg VERSION "$VERSION" --arg PLATFORM "$PLATFORM" \
      '.versions[] | select(.version | startswith($VERSION)) | .version as $v | .downloads.chrome[] | select(.platform == $PLATFORM) | [$v, .url] | @tsv' \
    | column -t
}

function list_chromium_cef_versions {
  local VERSION="$1"
  local PLATFORM="$2"

  curl -sL "$CHROMIUM_CEF_VERSION_API_JSON" \
    | jq -r \
      --arg VERSION "$VERSION" --arg PLATFORM "$PLATFORM" --arg URL_ROOT "$CHROMIUM_CEF_VERSION_API/" \
      '.[$PLATFORM].versions | reverse | .[] | select(.chromium_version | startswith($VERSION)) | .chromium_version as $v | .files[] | select(.type == "client") | [$v, $URL_ROOT + .name] | @tsv' \
    | column -t
}

function main {
  local VERSION=""
  local PLATFORM="mac-arm64"
  local COMMAND="install"
  local APP="chromium"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) VERSION="$2"; shift 2 ;;
      --platform) PLATFORM="$2"; shift 2 ;;
      --app) APP="$2"; shift 2 ;;
      --*) echo_error "Unknown option: $1" && exit 1 ;;
      *) COMMAND="$1"; shift ;;
    esac
  done

  if [[ -z "$VERSION" || -z "$PLATFORM" || -z "$APP" ]]; then
    echo_error "Usage: $0 [install|search] --version <version> --platform <platform> --app <app>"
    exit 1
  fi

  check_dependencies || exit 1

  case "$APP" in
    chromium)
      case "$COMMAND" in
        install) install_chromium "$VERSION" "$PLATFORM" || exit 1 ;;
        search) list_chromium_versions "$VERSION" "$PLATFORM" || exit 1 ;;
        *) echo_error "Invalid command: $COMMAND. Use 'install' or 'search'." && exit 1 ;;
      esac
    ;;
    cef)
      if [[ "$PLATFORM" == "mac-arm64" ]]; then
        echo_soft_warn "Automatically converting platform for CEF. 'mac-arm64' should be specified as 'macosarm64'."
        PLATFORM="macosarm64"
      fi
      case "$COMMAND" in
        install) install_chromium_cef "$VERSION" "$PLATFORM" || exit 1 ;;
        search) list_chromium_cef_versions "$VERSION" "$PLATFORM" || exit 1 ;;
        *) echo_error "Invalid command: $COMMAND. Use 'install' or 'search'." && exit 1 ;;
      esac
    ;;
    *) echo_error "Invalid app: $APP. Use 'chromium' or 'cef'." && exit 1 ;;
  esac
}

main "$@"