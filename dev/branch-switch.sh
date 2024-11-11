#!/usr/bin/env bash
# ---------------------------
# Author: Brandon Patram
# Date: 2022-11-16
#
# Description: Update developer environment after switching branches.
# This includes updating app dependencies and migrating databases.
#
# NOTE: This is very specific to a certain Rails application setup.
#
# Usage: branch-switch.sh [$(pwd)]
# Options:
# $1 specify path to local repo. When omitted the current directory is used
# ---------------------------

APP_DIRECTORY=${1:-$PWD}
DATABASE_DOCKER_SERVICE_NAME="postgres14"
BUNDLER_GEMFILE_LOCK_FILE="Gemfile.lock"
RUBY_VERSION_FILE=".ruby-version"
NODE_VERSION_FILE=".node-version"
WEB_SERVER_PID_FILE="$APP_DIRECTORY/tmp/pids/server.pid"
WEB_SERVER_PID=$(cat "$WEB_SERVER_PID_FILE" 2>/dev/null)
CONTAINER_PROVIDER=""

function determine_container_provider() {
  local PREFERRED_CONTAINER_PROVIDER="podman"
  local FOUND_PROVIDERS=()

  echo -n "Checking container provider... "

  if is_command_found "docker"; then
    FOUND_PROVIDERS+=("docker")
  fi

  if is_command_found "podman"; then
    FOUND_PROVIDERS+=("podman")
  fi

  if [ ${#FOUND_PROVIDERS[@]} -eq 0 ]; then
    echo "none found! Install a container provider (Docker or Podman)"
    return 1
  fi

  echo -n "${FOUND_PROVIDERS[*]}"

  if [ ${#FOUND_PROVIDERS[@]} -gt 1 ]; then
    if [[ "${FOUND_PROVIDERS[*]}" =~ $PREFERRED_CONTAINER_PROVIDER ]]; then
      export CONTAINER_PROVIDER="$PREFERRED_CONTAINER_PROVIDER"
      echo " ... ok! (using preferred: $CONTAINER_PROVIDER)"
    else
      export CONTAINER_PROVIDER="${FOUND_PROVIDERS[-1]}"
      echo " ... ok! (using: $CONTAINER_PROVIDER)"
    fi
  else
    export CONTAINER_PROVIDER="${FOUND_PROVIDERS[0]}"
    echo " ... ok!"
  fi
}

function is_compose_service_running() {
  local SERVICE_NAME="$1"
  case "$CONTAINER_PROVIDER" in
  "docker")
    docker ps --format="{{.Names}}" 2>/dev/null | grep -q "$SERVICE_NAME"
    ;;
  "podman")
    podman ps --format="{{.Names}}" 2>/dev/null | grep -q "$SERVICE_NAME"
    ;;
  esac
}

function stop_compose_service() {
  local SERVICE_NAME="$1"
  case "$CONTAINER_PROVIDER" in
  "docker")
    docker compose stop "$SERVICE_NAME"
    ;;
  "podman")
    podman-compose stop "$SERVICE_NAME"
    ;;
  esac
}

function start_compose_service() {
  local SERVICE_NAME="$1"
  case "$CONTAINER_PROVIDER" in
  "docker")
    docker compose start "$SERVICE_NAME"
    ;;
  "podman")
    podman-compose start "$SERVICE_NAME"
    ;;
  esac
}

function is_process_running() {
  local PID="$1"
  if [ -z "$PID" ]; then
    return 1
  fi
  ps -p "$PID" -o "pid=" | grep -q "$PID"
}

function is_web_server_running() {
  is_process_running "$WEB_SERVER_PID"
}

function is_database_running() {
  is_compose_service_running "$DATABASE_COMPOSE_SERVICE_NAME"
}

function is_command_found() {
  local COMMAND="$1"
  command -v "$COMMAND" >/dev/null 2>/dev/null
}

function is_gem_installed() {
  local GEM_NAME="$1"
  gem list -i "^${GEM_NAME}\$" >/dev/null 2>/dev/null
}

# function is_string_contains() {
#   local STR="$1"
#   local SUB="$2"
#   grep -q "$SUB" <<<"$STR"
# }

function ask() {
  local RESPONSE
  local QUESTION="${1:-Do you want to proceed?}"
  while true; do
    read -rp "$QUESTION (y/N) " RESPONSE
    case $RESPONSE in
    [yY])
      return 0
      ;;
    [nN])
      return 1
      ;;
    *)
      echo "Invalid response"
      ;;
    esac
  done
}

function stop_database_service() {
  echo -n "Stopping database compose service... "
  if stop_compose_service "$DATABASE_COMPOSE_SERVICE_NAME" >/dev/null 2>/dev/null; then
    echo "stopped!"
    return 0
  else
    echo "failed to stop!"
    return 1
  fi
}

function start_database_service() {
  echo -n "Starting database compose service... "
  start_compose_service "$DATABASE_COMPOSE_SERVICE_NAME" >/dev/null 2>/dev/null &
  sleep 10
  echo "probably started by now, moving on!"
}

function stop_web_server() {
  if [ -z "$WEB_SERVER_PID" ]; then
    kill "$WEB_SERVER_PID"
  fi
}

function ensure_system_dependencies() {
  echo -n "Checking required system dependencies: "
  if is_command_found "node"; then
    echo -n "node "
  else
    echo "Missing node command. Install Node." && return 1
  fi
  if is_command_found "ruby"; then
    echo -n "ruby "
  else
    echo "Missing ruby command. Install Ruby." && return 1
  fi
  if is_command_found "bundle"; then
    echo -n "bundle "
  else
    echo "Missing bundle command. Install Bundler." && return 1
  fi
  if is_command_found "gem"; then
    echo -n "gem "
  else
    echo "Missing gem command. Install Bundler." && return 1
  fi

  echo "... ok!"
}

function ensure_misc_system_dependencies() {
  local NEEDS_RIPPER_TAGS=true
  local NEEDS_DEBUG=true

  echo -n "Checking optional system dependencies: "

  echo -n "debug "
  if is_gem_installed "debug"; then
    NEEDS_DEBUG=false
  fi

  # ripper-tags is just needed for the bust-a-gem vscode extension
  echo -n "ripper-tags "
  if is_gem_installed "ripper-tags"; then
    NEEDS_RIPPER_TAGS=false
  fi

  if [ $NEEDS_RIPPER_TAGS = false ] && [ $NEEDS_DEBUG = false ]; then
    echo "... ok!"
  else
    echo "... missing!"
  fi

  if [ $NEEDS_DEBUG = true ]; then
    if ask "Missing Ruby debug gem. Install now?"; then
      gem install 'debug' || return 1
    fi
  fi

  if [ $NEEDS_RIPPER_TAGS = true ]; then
    if ask "Missing Ruby ripper-tags gem. Install now?"; then
      gem install 'ripper-tags' || return 1
    fi
  fi
}

function ensure_ruby_version() {
  echo -n "Checking Ruby version... "
  CURRENT_RUBY_VERSION=$(ruby -v | sed -E 's/ruby ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
  EXPECTED_RUBY_VERSION=$(cat "$RUBY_VERSION_FILE")

  if [ "$CURRENT_RUBY_VERSION" = "$EXPECTED_RUBY_VERSION" ]; then
    echo "ok! (using version: $CURRENT_RUBY_VERSION)"
    return 0
  else
    echo "outdated! Expected version $EXPECTED_RUBY_VERSION but received version $CURRENT_RUBY_VERSION"

    echo -n "Checking for Ruby vm... "
    if is_command_found "rbenv"; then
      echo "rbenv found!"

      echo "Installing Ruby $EXPECTED_RUBY_VERSION... "
      rbenv install || return 1

      return 0
    else
      echo "none found. aborting..."
      return 1
    fi
  fi
}

function ensure_node_version() {
  echo -n "Checking Node version... "
  CURRENT_NODE_VERSION=$(node -v | sed -e 's/v//')
  EXPECTED_NODE_VERSION=$(cat "$NODE_VERSION_FILE")

  if [ "$CURRENT_NODE_VERSION" = "$EXPECTED_NODE_VERSION" ]; then
    echo "ok! (using version: $CURRENT_NODE_VERSION)"
    return 0
  else
    echo "outdated! Expected version $EXPECTED_NODE_VERSION but received version $CURRENT_NODE_VERSION"
    echo -n "Checking for Node vm... "
    if is_command_found "nodenv"; then
      echo "nodenv found!"

      echo "Installing Node $EXPECTED_NODE_VERSION... "
      nodenv install -fs || return 1
    else
      echo "none found. aborting..."
      return 1
    fi
  fi
}

function ensure_ruby_package_manager() {
  echo -n "Checking Ruby package manager... "
  if [ -f Gemfile.lock ]; then
    ensure_bundle_version || return 1
  else
    echo "unknown"
    return 0
  fi
}

function ensure_bundle_version() {
  # echo -n "Checking Bundler version... "
  CURRENT_BUNDLE_VERSION=$(grep -A1 'BUNDLED WITH' "$BUNDLER_GEMFILE_LOCK_FILE" | sed 's/BUNDLED WITH//g' | tr -d '[:space:]')
  CURRENT_BUNDLER_VERSION=$(bundle --version | sed 's/Bundler version//' | tr -d '[:space:]')

  if [ "$CURRENT_BUNDLE_VERSION" = "$CURRENT_BUNDLER_VERSION" ]; then
    echo "Bundler ok! (using version: $CURRENT_BUNDLER_VERSION)"
  else
    echo "outdated! Expected version ${CURRENT_BUNDLE_VERSION} but received version ${CURRENT_BUNDLER_VERSION}"
    echo -n "Updating bundler... "
    if ! gem install "bundler:$CURRENT_BUNDLE_VERSION" --silent; then
      echo "failed."
      return 1
    fi
    echo "updated!"
    return 0
  fi
}

function ensure_node_package_manager() {
  echo -n "Checking Node package manager... "
  if [ -f yarn.lock ]; then
    ensure_yarn_version || return 1
  else
    echo "unknown"
    return 0
  fi
}

function ensure_yarn_version() {
  # echo -n "Checking for Yarn... "
  CURRENT_YARN_VERSION=$(yarn -v 2>/dev/null)
  if [ -z "$CURRENT_YARN_VERSION" ]; then
    echo "not found!"

    echo "Installing Yarn globally... "
    npm install -g --quiet --no-fund yarn || return 1
  else
    echo "Yarn ok! (using version: $CURRENT_YARN_VERSION)"
  fi
}

function install_project_dependencies() {
  echo -n "Installing Node and Ruby project dependencies... "

  # running both in parallel for speeeed
  yarn install --silent &
  bundle install --quiet &
  wait

  # re-echoing since one those those commands clear the screen
  echo -n "Installing Node and Ruby project dependencies... "
  echo "done!"
}

function restart_web_server() {
  if [ -z "$WEB_SERVER_PID" ]; then
    echo -n "Restarting server... "
    # sending the USR2 signal will cause a restart
    # https://github.com/puma/puma/blob/master/docs/restart.md
    kill -s USR2 "$WEB_SERVER_PID"
    echo "restarted!"
  fi
}

function is_database_service_running() {
  echo -n "Checking for database container service... "

  if is_database_running; then
    echo "running!"
    return 0
  else
    echo "not running!"
    return 1
  fi
}

function migrate_databases() {
  local DATABASE_PENDING_MIGRATIONS
  local DATABASE_HAS_MIGRATIONS
  local DATABASE_NOT_EXISTS
  local DATABASE_NOT_ACCESSIBLE

  echo -n "Checking database migration status... "

  DATABASE_PENDING_MIGRATIONS=$(bundle exec rails db:abort_if_pending_migrations 2>&1 >/dev/null)
  DATABASE_HAS_MIGRATIONS="$?" # must be right after db:abort_if_pending_migrations command in order to get exit code
  DATABASE_NOT_EXISTS=$(
    echo "$DATABASE_PENDING_MIGRATIONS" | grep -q "ActiveRecord::NoDatabaseError"
    echo $?
  )
  DATABASE_NOT_ACCESSIBLE=$(
    echo "$DATABASE_PENDING_MIGRATIONS" | grep -q "ActiveRecord::ConnectionNotEstablished"
    echo $?
  )

  if [ "$DATABASE_NOT_ACCESSIBLE" -eq "0" ]; then
    echo "unable to connect to database"
    return 1
  fi

  if [ "$DATABASE_NOT_EXISTS" -eq "0" ]; then
    echo "no database!"

    echo "Creating databases..."
    if ! bundle exec rails db:create:all db:schema:load:with_data; then
      echo "Aborting... something is wrong with your database, database service, or database connection"
      return 1
    else
      echo "Finished database creation and migrations!"
      return 0
    fi
  fi

  if [ "$DATABASE_HAS_MIGRATIONS" -eq "0" ]; then
    echo "up to date!"
    return 0
  else
    echo "pending migrations found!"
  fi

  echo "Migrating database schemas and data... "

  if ! bundle exec rails db:migrate:ops db:migrate:with_data; then
    echo "Failed to migrate database"
    return 1
  else
    echo "Finished database migrations!"
  fi
}

######################################
##               main               ##
######################################

function main() {
  echo "Running for app in directory: $APP_DIRECTORY"
  cd "$APP_DIRECTORY" || return 1

  export DISABLE_SPRING=1 # disble spring for all rails commands ran

  ensure_system_dependencies || return 1
  determine_container_provider || return 1
  ensure_ruby_version || return 1
  ensure_node_version || return 1
  ensure_ruby_package_manager || return 1
  ensure_node_package_manager || return 1
  ensure_misc_system_dependencies || return 1
  install_project_dependencies || return 1

  if is_database_service_running; then
    migrate_databases || return 1
  else
    if ask "Do you want to attempt to start the database service?"; then
      start_database_service || return 1
      if migrate_databases; then
        stop_database_service || return 1
      else
        stop_database_service
        return 1
      fi
    else
      echo "Skipped migrations"
    fi
  fi

  if is_web_server_running; then
    restart_web_server
  fi

  echo "Done!"
}

main "$@"
