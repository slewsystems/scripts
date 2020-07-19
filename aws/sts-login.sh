#!/usr/bin/env bash

# ---------------------------
# Author: Brandon Patram
# Date: 2020-05-11
#
# Description: Login to AWS CLI using MFA. Will create a new AWS profile
# postfixed with '-mfa' for your sts session.
#
# Usage: sts-login.sh -t "MFA_TOKEN_CODE" -s "arn:aws:iam:MFA_ARN/USERNAME" [-p PROFILE_NAME="default"]
# ---------------------------

SILENCE=false
SESSION_PROFILE_ENDING="-mfa"
DEFAULT_AWS_REGION="us-east-1"

function echo_error() { echo -e "\\033[0;31m[ERROR] $*\\033[0m"; }
function echo_warn() { echo -e "\\033[0;33m[WARN] $*\\033[0m"; }
function echo_soft_warn() { if [ "$SILENCE" = false ]; then echo -e "\\033[0;33m$*\\033[0m"; fi; }
function echo_success() { if [ "$SILENCE" = false ]; then echo -e "\\033[0;32m$*\\033[0m"; fi; }
function echo_info() { if [ "$SILENCE" = false ]; then echo -e "$*\\033[0m"; fi; }

function ensure_requirements() {
    if ! [ -x "$(command -v aws)" ]; then
        echo_error "Missing aws command. To install run: brew install awscli"
        return 1
    fi

    if ! [ -x "$(command -v jq)" ]; then
        echo_error "Missing jq command. To install run: brew install jq"
        return 1
    fi
}

function check_profile() {
    local profile
    profile="$1"

    if ! aws --profile "$profile" configure list >/dev/null; then
        return 1
    fi
}

function get_session_profile_name() {
    local profile
    profile="$1"

    echo "${profile}$SESSION_PROFILE_ENDING"
}

function configure_session_profile() {
    local token_code mfa_serial_number profile

    token_code="$1"
    mfa_serial_number="$2"
    main_profile="$3"
    session_profile=$(get_session_profile_name "$main_profile")

    local json_credentials access_key secret_access_key session_token expires

    json_credentials=$(aws --profile "$main_profile" sts get-session-token --serial-number "$mfa_serial_number" --token-code "$token_code")

    access_key=$(echo "$json_credentials" | jq -r ".Credentials.AccessKeyId")
    secret_access_key=$(echo "$json_credentials" | jq -r ".Credentials.SecretAccessKey")
    session_token=$(echo "$json_credentials" | jq -r ".Credentials.SessionToken")
    expires=$(echo "$json_credentials" | jq -r ".Credentials.Expiration")

    if [ -z "$access_key" ] || [ -z "$secret_access_key" ] || [ -z "$session_token" ]; then
        return 1
    fi

    echo_soft_warn "Your session expires on $expires"

    aws configure --profile "$session_profile" set aws_access_key_id "$access_key" &&
        aws configure --profile "$session_profile" set aws_secret_access_key "$secret_access_key" &&
        aws configure --profile "$session_profile" set aws_session_token "$session_token" &&
        aws configure --profile "$session_profile" set region "$DEFAULT_AWS_REGION"
}

function main() {
    local token_code mfa_serial_number profile sessioned_profile
    profile="default"

    while getopts "h:p:t:s:q" opt; do
        case "${opt}" in
        t)
            token_code="$OPTARG"
            ;;
        q)
            SILENCE=true
            ;;
        s)
            mfa_serial_number="$OPTARG"
            ;;
        p)
            profile="$OPTARG"
            ;;
        h)
            echo -e "Usage:\nsts-login.sh [-t token_code] [-s serial_number_arn] [-p profile-name]" && return 0
            ;;
        \?)
            echo "Invalid Option: -$OPTARG" 1>&2
            return 1
            ;;
        esac
    done

    sessioned_profile=$(get_session_profile_name "$profile")

    ensure_requirements || return 1

    # TODO: attempt to get last mfa serial number instead of requiring it everytime

    if [ -z "$mfa_serial_number" ]; then
        echo_error "Missing MFA serial number! Retry using the -s flag"
        return 1
    fi

    if [ -z "$token_code" ]; then
        echo_error "Missing MFA rotating token! Retry using the -t flag"
        return 1
    fi

    echo_info "Checking master AWS credentials for \"$profile\"..."
    if ! check_profile "$profile"; then
        echo_error "Your master AWS credentials are invalid... run \`aws --profile \"$profile\" configure\` to fix"
        return 1
    fi

    echo_info "Using \"$profile\" profile to regenerate session profile \"$sessioned_profile\" ..."

    if configure_session_profile "$token_code" "$mfa_serial_number" "$profile"; then
        aws --profile "$sessioned_profile" configure list

        echo_success "Done! Use the \"$sessioned_profile\" profile when interacting with AWS CLI"
    else
        echo_error "Failed to regenerate \"$sessioned_profile\" profile"
    fi

}
main "$@"
