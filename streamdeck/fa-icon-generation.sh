#!/usr/bin/env bash
set -e

# ---------------------------
# Author: Brandon Patram
# Date: 2026-04-13
#
# Description: Generates PNG icons from FA. Intended to be used for Stream Deck (or its clones) when adding
# new buttons to your device. This script will download the FA icons and convert them with additional padding.
#
# Usage: fa-icon-generation.sh [options] <icon-name>
# Options:
#  --icon-set:  Icon set to use (fa-solid, fa-regular, or feather)
#  --output:    Output directory (e.g., "output")
#  --size:      Size of the icon in pixels
#  --padding:   Padding around the icon in pixels
#  --fill-color:       Fill color for the icon (default: #006c7a)
#  --stroke-color:     Stroke color for the icon (default: same as fill color)
#  --stroke-width:     Stroke width for the icon (default: 0)
#  --background-color: Background color (default: transparent)
#  --label-color: Label color (default: white)
#  --label-top:    Label text to display at the top of the icon
#  --label-center: Label text to display at the center of the icon
#  --label-bottom: Label text to display at the bottom of the icon
#  --label-size:   Font size for labels (default: 15)
#  --label-font:    Font for labels (default: /System/Library/Fonts/SFNS.ttf)
#  --label-padding:      Padding for labels from edge (default: 2)
#  --label-stroke-color: Stroke color for label text (default: black)
#  --label-stroke-width: Stroke width for label text glow (default: 2)
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

  # rsvg-convert is required for proper SVG rendering (stroke, line, rect, etc.)
  if ! is_command_found rsvg-convert; then
    echo_error "Missing rsvg-convert command (librsvg). Install with: brew install librsvg"
    exit 1
  fi
}

function download_sprite_sheet {
  local ICON_SET="$1"
  local SVG_SAVE_PATH="$2"

  case "$ICON_SET" in
    fa-solid) SVG_URL="https://raw.githubusercontent.com/FortAwesome/Font-Awesome/refs/heads/7.x/sprites/solid.svg" ;;
    fa-regular) SVG_URL="https://raw.githubusercontent.com/FortAwesome/Font-Awesome/refs/heads/7.x/sprites/regular.svg" ;;
    feather) SVG_URL="https://unpkg.com/feather-icons/dist/feather-sprite.svg" ;;
    *) echo_error "Invalid icon set: $ICON_SET. Use 'fa-solid', 'fa-regular', or 'feather'." && exit 1 ;;
  esac

  echo -n "Downloading ${ICON_SET} sprite sheet... "
  if [[ ! -f "$SVG_SAVE_PATH" ]]; then
    mkdir -p "$(dirname "$SVG_SAVE_PATH")"
    curl -s -L -o "$SVG_SAVE_PATH" "$SVG_URL"
    echo_success "Downloaded ${ICON_SET} sprite sheet to $SVG_SAVE_PATH"
  else
    echo_soft_warn "Sprite sheet for ${ICON_SET} already exists. Skipping download."
  fi
}

function extract_sprite_symbol {
  local SPRITE_SHEET_SVG_PATH="$1"
  SYMBOL_ID="$2"

  echo -n "Extracting symbol '$SYMBOL_ID' from sprite sheet... "
  # Normalize so each <symbol> and </symbol> tag starts on its own line,
  # then extract the target block. The closing </symbol> sed quits after
  # the first match to avoid the sed range double-match issue when
  # start and end patterns appear on the same line.
  NORMALIZED=$(sed $'s/<symbol/\\\n<symbol/g; s/<\\/symbol>/<\\/symbol>\\\n/g' "$SPRITE_SHEET_SVG_PATH")
  SYMBOL_BLOCK=$(echo "$NORMALIZED" | sed -n "/<symbol id=\"${SYMBOL_ID}\"/,/<\/symbol>/{p; /<\/symbol>/q;}")

  if [[ -z "$SYMBOL_BLOCK" ]]; then
    echo_error "Symbol '$SYMBOL_ID' not found in sprite sheet"
    exit 1
  fi

  # Derive viewBox and inner paths from the extracted symbol
  SYMBOL_VIEWBOX=$(echo "$SYMBOL_BLOCK" | sed -n "s/.*viewBox=\"\([^\"]*\)\".*/\1/p")
  SYMBOL_PATHS=$(echo "$SYMBOL_BLOCK" | sed 's/<symbol[^>]*>//;s/<\/symbol>//')

  echo_success "Done!"
}

function create_png_icon {
  local FILL_COLOR="$1"
  local STROKE_COLOR="$2"
  local STROKE_WIDTH="$3"
  local PNG_SAVE_PATH="$4"
  local SIZE="$5"
  local PADDING="$6"
  local LABEL_TOP="$7"
  local LABEL_CENTER="$8"
  local LABEL_BOTTOM="$9"
  local LABEL_COLOR="${10}"
  local LABEL_SIZE="${11}"
  local LABEL_FONT="${12}"
  local LABEL_PADDING="${13}"
  local LABEL_STROKE_COLOR="${14}"
  local BACKGROUND_COLOR="${15}"
  local LABEL_STROKE_WIDTH="${16}"

  # Calculate inner size by subtracting padding from each side
  local WIDTH="${SIZE%x*}"
  local HEIGHT="${SIZE#*x}"
  local INNER_WIDTH=$(( WIDTH - PADDING * 2 ))
  local INNER_HEIGHT=$(( HEIGHT - PADDING * 2 ))

  # Build glow + fill label args
  # Glow: draw text on a transparent layer, blur it, composite onto the image
  # Fill: draw crisp text on top
  local LABEL_ARGS=()
  local GLOW_ARGS=(-font "$LABEL_FONT" -fill "$LABEL_STROKE_COLOR" -stroke "$LABEL_STROKE_COLOR" -strokewidth "$LABEL_STROKE_WIDTH" -pointsize "$LABEL_SIZE")
  local FILL_ARGS=(-font "$LABEL_FONT" -fill "$LABEL_COLOR" -stroke none -pointsize "$LABEL_SIZE")

  local GLOW_ANNOTATIONS=()
  local FILL_ANNOTATIONS=()
  if [[ -n "$LABEL_TOP" ]]; then
    GLOW_ANNOTATIONS+=(-gravity north "${GLOW_ARGS[@]}" -annotate "+0+$LABEL_PADDING" "$LABEL_TOP")
    FILL_ANNOTATIONS+=(-gravity north "${FILL_ARGS[@]}" -annotate "+0+$LABEL_PADDING" "$LABEL_TOP")
  fi
  if [[ -n "$LABEL_CENTER" ]]; then
    GLOW_ANNOTATIONS+=(-gravity center "${GLOW_ARGS[@]}" -annotate "+0+0" "$LABEL_CENTER")
    FILL_ANNOTATIONS+=(-gravity center "${FILL_ARGS[@]}" -annotate "+0+0" "$LABEL_CENTER")
  fi
  if [[ -n "$LABEL_BOTTOM" ]]; then
    GLOW_ANNOTATIONS+=(-gravity south "${GLOW_ARGS[@]}" -annotate "+0+$LABEL_PADDING" "$LABEL_BOTTOM")
    FILL_ANNOTATIONS+=(-gravity south "${FILL_ARGS[@]}" -annotate "+0+$LABEL_PADDING" "$LABEL_BOTTOM")
  fi

  if [[ ${#GLOW_ANNOTATIONS[@]} -gt 0 ]]; then
    # Create a blank transparent canvas for glow text, blur it, composite under crisp fill text
    LABEL_ARGS+=(
      \( -size "$SIZE" xc:none "${GLOW_ANNOTATIONS[@]}" -blur "0x$LABEL_STROKE_WIDTH" \)
      -composite
      "${FILL_ANNOTATIONS[@]}"
    )
  fi

  echo -n "Generating ${SIZE} PNG icon... "
  mkdir -p "$(dirname "$PNG_SAVE_PATH")"

  # Build SVG in memory, rasterize with rsvg-convert, then pipe to ImageMagick for padding/labels
  local SVG_CONTENT
  SVG_CONTENT="<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"$SYMBOL_VIEWBOX\">"
  SVG_CONTENT+="<g fill=\"$FILL_COLOR\" stroke=\"$STROKE_COLOR\" stroke-width=\"$STROKE_WIDTH\" stroke-linecap=\"round\" stroke-linejoin=\"round\">"
  SVG_CONTENT+="$(echo "$SYMBOL_PATHS" | sed "s/currentColor/$FILL_COLOR/g")"
  SVG_CONTENT+="</g></svg>"

  if echo "$SVG_CONTENT" \
    | rsvg-convert -w "$INNER_WIDTH" -h "$INNER_HEIGHT" --keep-aspect-ratio -b "$BACKGROUND_COLOR" \
    | magick png:- -gravity center -background "$BACKGROUND_COLOR" -extent "$SIZE" "${LABEL_ARGS[@]}" "$PNG_SAVE_PATH" ; then
    echo_success "Done! $PNG_SAVE_PATH"
  else
    echo_error "Failed to generate PNG icon"
    exit 1
  fi
}

function main() {
  # default values
  export ICON_NAME=""
  export OUTPUT_PATH="output"
  export ICON_SIZE="128x128"
  export ICON_SET="fa-solid"
  export PADDING="30"
  export FILL_COLOR="#006c7a"
  export STROKE_COLOR=""
  export STROKE_WIDTH="0"
  export LABEL_COLOR="white"
  export LABEL_TOP=""
  export LABEL_CENTER=""
  export LABEL_BOTTOM=""
  export LABEL_SIZE="15"
  export LABEL_FONT="/System/Library/Fonts/SFNS.ttf"
  export LABEL_PADDING="2"
  export LABEL_STROKE_COLOR="black"
  export LABEL_STROKE_WIDTH="2"
  export BACKGROUND_COLOR="none"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --icon-set) ICON_SET="$2"; shift 2 ;;
      --size) ICON_SIZE="$2"; shift 2 ;;
      --output) OUTPUT_PATH="$2"; shift 2 ;;
      --padding) PADDING="$2"; shift 2 ;;
      --fill-color) FILL_COLOR="$2"; shift 2 ;;
      --stroke-color) STROKE_COLOR="$2"; shift 2 ;;
      --stroke-width) STROKE_WIDTH="$2"; shift 2 ;;
      --label-color) LABEL_COLOR="$2"; shift 2 ;;
      --label-top) LABEL_TOP="$2"; shift 2 ;;
      --label-center) LABEL_CENTER="$2"; shift 2 ;;
      --label-bottom) LABEL_BOTTOM="$2"; shift 2 ;;
      --label-size) LABEL_SIZE="$2"; shift 2 ;;
      --label-font) LABEL_FONT="$2"; shift 2 ;;
      --label-padding) LABEL_PADDING="$2"; shift 2 ;;
      --label-stroke-color) LABEL_STROKE_COLOR="$2"; shift 2 ;;
      --label-stroke-width) LABEL_STROKE_WIDTH="$2"; shift 2 ;;
      --background-color) BACKGROUND_COLOR="$2"; shift 2 ;;
      --*) echo_error "Unknown option: $1" && exit 1 ;;
      *) ICON_NAME="$1"; shift ;;
    esac
  done

  if [[ -z "$ICON_NAME" ]]; then
    echo_error "Icon name is required."
    exit 1
  fi

  check_dependencies || exit 1

  SVG_SPRITE_SHEET_PATH="$OUTPUT_PATH/svg/${ICON_SET}/sprite-sheet.svg"
  download_sprite_sheet "$ICON_SET" "$SVG_SPRITE_SHEET_PATH"

  extract_sprite_symbol "$SVG_SPRITE_SHEET_PATH" "$ICON_NAME" || exit 1
  # Default stroke color to fill color if not set
  [[ -z "$STROKE_COLOR" ]] && STROKE_COLOR="$FILL_COLOR"

  OUTPUT_FILE_NAME="$ICON_NAME"
  [[ -n "$LABEL_TOP" ]] && OUTPUT_FILE_NAME="${OUTPUT_FILE_NAME}-${LABEL_TOP}"
  [[ -n "$LABEL_CENTER" ]] && OUTPUT_FILE_NAME="${OUTPUT_FILE_NAME}-${LABEL_CENTER}"
  [[ -n "$LABEL_BOTTOM" ]] && OUTPUT_FILE_NAME="${OUTPUT_FILE_NAME}-${LABEL_BOTTOM}"
  OUTPUT_FILE_NAME=$(echo "$OUTPUT_FILE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

  OUTPUT_FILE="$OUTPUT_PATH/${ICON_SET}/${OUTPUT_FILE_NAME}.png"
  create_png_icon \
    "$FILL_COLOR" "$STROKE_COLOR" "$STROKE_WIDTH" \
    "$OUTPUT_FILE" "$ICON_SIZE" "$PADDING" \
    "$LABEL_TOP" "$LABEL_CENTER" "$LABEL_BOTTOM" \
    "$LABEL_COLOR" "$LABEL_SIZE" "$LABEL_FONT" "$LABEL_PADDING" "$LABEL_STROKE_COLOR" "$BACKGROUND_COLOR" "$LABEL_STROKE_WIDTH"
}

main "$@"