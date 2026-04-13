#!/usr/bin/env bash
set -e

# ---------------------------
# Author: Brandon Patram
# Date: 2026-04-13
#
# Description: Generates PNG icons from FA. Intended to be used for Stream Deck (or its clones) when adding
# new buttons to your device. This script will download the FA icons and convert them with additional padding.
#
# Usage: fa-icon-generation.sh [options] [label]
# Options:
#  --style:     Style of the icon (solid or regular)
#  --icon:      Name of the icon (e.g., "coffee", "camera", etc.)
#  --output:    Output directory (e.g., "output")
#  --size:      Size of the icon in pixels
#  --padding:   Padding around the icon in pixels
#  --color:       Primary color (default: black)
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

function check_dependencies {
  if ! is_command_found magick; then
    echo_error "Missing Imagemagick (magick) command! Install and try again."
    exit 1
  fi
}

function download_sprite_sheet {
  local STYLE="$1"
  local SVG_SAVE_PATH="$2"

  case "$STYLE" in
    solid) SVG_URL="https://raw.githubusercontent.com/FortAwesome/Font-Awesome/refs/heads/7.x/sprites/solid.svg" ;;
    regular) SVG_URL="https://raw.githubusercontent.com/FortAwesome/Font-Awesome/refs/heads/7.x/sprites/regular.svg" ;;
    *) echo_error "Invalid style: $STYLE. Use 'solid' or 'regular'." && exit 1 ;;
  esac

  echo_info "Downloading ${STYLE} sprite sheet..."
  if [[ ! -f "$SVG_SAVE_PATH" ]]; then
    mkdir -p "$(dirname "$SVG_SAVE_PATH")"
    curl -s -L -o "$SVG_SAVE_PATH" "$SVG_URL"
    echo_success "Downloaded ${STYLE} sprite sheet to $SVG_SAVE_PATH"
  else
    echo_soft_warn "Sprite sheet for ${STYLE} already exists. Skipping download."
  fi
}

function extract_sprite_symbol {
  local SPRITE_SHEET_SVG_PATH="$1"
  SYMBOL_ID="$2"

  # Extract the full <symbol>...</symbol> block once
  SYMBOL_BLOCK=$(sed -n "/<symbol id=\"${SYMBOL_ID}\"/,/<\/symbol>/p" "$SPRITE_SHEET_SVG_PATH")

  if [[ -z "$SYMBOL_BLOCK" ]]; then
    echo_error "Symbol '$SYMBOL_ID' not found in sprite sheet"
    exit 1
  fi

  # Derive viewBox and inner paths from the extracted symbol
  SYMBOL_VIEWBOX=$(echo "$SYMBOL_BLOCK" | sed -n "s/.*viewBox=\"\([^\"]*\)\".*/\1/p")
  SYMBOL_PATHS=$(echo "$SYMBOL_BLOCK" | sed '/<symbol/d; /<\/symbol>/d')

  echo_success "Extracted symbol '$SYMBOL_ID' (viewBox: $SYMBOL_VIEWBOX)"
}

function create_svg_icon {
  local FILL_COLOR="$1"
  local SVG_SAVE_PATH="$2"

  echo_info "Generating icon SVG..."
  mkdir -p "$(dirname "$SVG_SAVE_PATH")"

  # Build a standalone SVG, replacing currentColor with the fill color
  {
    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"$SYMBOL_VIEWBOX\">"
    echo "$SYMBOL_PATHS" | sed "s/currentColor/$FILL_COLOR/g"
    echo "</svg>"
  } > "$SVG_SAVE_PATH"

  echo_success "Generated SVG icon at $SVG_SAVE_PATH"
}

function create_png_icon {
  local SVG_PATH="$1"
  local PNG_SAVE_PATH="$2"
  local SIZE="$3"
  local PADDING="$4"

  # Calculate inner size by subtracting padding from each side
  local WIDTH="${SIZE%x*}"
  local HEIGHT="${SIZE#*x}"
  local INNER_WIDTH=$(( WIDTH - PADDING * 2 ))
  local INNER_HEIGHT=$(( HEIGHT - PADDING * 2 ))

  echo_info "Generating ${SIZE} PNG icon (padding: ${PADDING}px) from $SVG_PATH..."
  mkdir -p "$(dirname "$PNG_SAVE_PATH")"
  if magick -background none "$SVG_PATH" -resize "${INNER_WIDTH}x${INNER_HEIGHT}" -gravity center -extent "$SIZE" "$PNG_SAVE_PATH" ; then
    echo_success "Generated PNG icon at $PNG_SAVE_PATH"
  else
    echo_error "Failed to generate PNG icon from $SVG_PATH"
    exit 1
  fi
}

function main() {
  # default values
  export ICON_NAME="camera"
  export OUTPUT_PATH="output"
  export ICON_SIZE="128x128"
  export STYLE="solid"
  export PADDING="30"
  export PRIMARY_COLOR="#006c7a"
  export LABEL_COLOR="white"
  export LABEL_TEXT=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --style) STYLE="$2"; shift 2 ;;
      --icon) ICON_NAME="$2"; shift 2 ;;
      --size) ICON_SIZE="$2"; shift 2 ;;
      --output) OUTPUT_PATH="$2"; shift 2 ;;
      --padding) PADDING="$2"; shift 2 ;;
      --color) PRIMARY_COLOR="$2"; shift 2 ;;
      --*) echo_error "Unknown option: $1" && exit 1 ;;
      *) echo_error "Unexpected argument: $1" && exit 1 ;;
    esac
  done

  check_dependencies || exit 1

  SVG_SPRITE_SHEET_PATH="$OUTPUT_PATH/svg/${STYLE}/sprite-sheet.svg"
  download_sprite_sheet "$STYLE" "$SVG_SPRITE_SHEET_PATH"

  extract_sprite_symbol "$SVG_SPRITE_SHEET_PATH" "$ICON_NAME" || exit 1
  SVG_SPRITE_PATH="$OUTPUT_PATH/svg/${STYLE}/symbols/${ICON_NAME}.svg"
  create_svg_icon "$PRIMARY_COLOR" "$SVG_SPRITE_PATH"

  OUTPUT_FILE="$OUTPUT_PATH/${STYLE}/${ICON_NAME}.png"
  create_png_icon "$SVG_SPRITE_PATH" "$OUTPUT_FILE" "$ICON_SIZE" "$PADDING"
}

main "$@"