#!/usr/bin/env bash

# Supported certbot plugins
readonly VALID_CERTBOT_PLUGINS=("cloudflare" "linode")

# This function reads the docker secrets based variables defined with pattern *_FILE into the normal variables
# usage: file_env VAR [DEFAULT]
#    ie: file_env 'DB_PASSWORD' 'default_password'
# (will allow for "$DB_PASSWORD_FILE" to fill in the value of
#  "$DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
  local var="$1"
  local fileVar="${var}_FILE"
  local def="${2:-}"
  if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
  	echo "Both $var and $fileVar are set (but are exclusive)"
  fi
  local val="$def"
  if [ "${!var:-}" ]; then
  	val="${!var}"
  elif [ "${!fileVar:-}" ]; then
  	val="$(< "${!fileVar}")"
  fi
  export "$var"="$val"
  unset "$fileVar"
}

# A simple utility function to check if a given value is present in array
# The first argument is the value to be checked
# The second argument is a bash array
# Example:
# readonly MODES=("up" "down")
# local current_mode="up"
# if ! contains_element "${current_mode}" "${MODES[@]}"; then
#   echo "Current mode is not valid value ${current_mode}"
#   echo "Valid values are: (${MODES[*]})"
#   exit -1
# else
#   echo "Found value: ${current_mode}"
# fi
contains_element () {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

_main() {
  # Each environment variable that supports the *_FILE pattern eeds to be passed into the file_env() function.
  file_env "CLOUDFLARE_API_TOKEN"
  file_env "LINODE_API_KEY"
  file_env "PKCS12_PASSWORD"

  # Test if CERTBOT_PLUGIN option was not present.
  if  [[ ! "${CERTBOT_PLUGIN}" ]] ; then
    # Test that VALID_CERTBOT_PLUGINS contains a valid value
    if ! contains_element "${CERTBOT_PLUGIN}" "${VALID_CERTBOT_PLUGINS[@]}"; then
      echo "[error] Certbot Plugin: ${CERTBOT_PLUGIN} is not supported! Supported values are: (${VALID_CERTBOT_PLUGINS[*]})"
      exit -1
    fi
  else
      echo "[info] Active Certbot Plugin is: ${CERTBOT_PLUGIN}"
  fi

  # Validate correct parameters are set
  if [[ "$CERTBOT_PLUGIN" = "cloudflare" ]]; then
    [[ -z "$CLOUDFLARE_API_TOKEN" ]] && echo "[error] CLOUDFLARE_API_TOKEN is unset" && exit -1 || echo "[info] CLOUDFLARE_API_TOKEN is set"
  fi

  if [[ "$CERTBOT_PLUGIN" = "linode" ]]; then
    [[ -z "$LINODE_API_KEY" ]] && echo "[error] LINODE_API_KEY is unset" && exit -1 || echo "[info] LINODE_API_KEY is set"
  fi

  if [[ "$PKCS12_ENABLE" = true ]]; then
    [[ -z "$PKCS12_PASSWORD" ]] && echo "[error] PKCS12_PASSWORD is unset" && exit -1 || echo "[info] PKCS12_PASSWORD is set"
  fi

  # First run
  /scripts/run_certbot.sh

  # Scheduling periodic executions
  exec crond -f
}

_main "$@"
