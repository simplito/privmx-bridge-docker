#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
VOLUMES_DIR=$DIR/volumes
ENV_FILE=$DIR/bridge.env

if [ -f $ENV_FILE ]; then
    source $ENV_FILE
fi

if [ -z $API_KEY_ID ] || [ -z $API_KEY_SECRET ]; then
    printf "API_KEY_ID and API_KEY_SECRET must be set (via env file or environment)\n"
    exit 1
fi

cd $DIR
docker compose exec -T -e API_KEY_ID=$API_KEY_ID -e API_KEY_SECRET=$API_KEY_SECRET privmx-bridge pmxbridge_cli "$@"
