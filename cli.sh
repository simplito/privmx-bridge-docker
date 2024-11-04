#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
VOLUMES_DIR=$DIR/volumes
ENV_FILE=$VOLUMES_DIR/.env

if [ ! -f $ENV_FILE ]; then
    printf "File with api key does not exist ($ENV_FILE)\n"
    exit 1
fi

source $ENV_FILE

if [ -z $API_KEY_ID ] || [ -z $API_KEY_SECRET ]; then
    printf "There is no api key in env file ($ENV_FILE)\n"
    exit 1
fi

cd $DIR
docker compose exec -T -e API_KEY_ID=$API_KEY_ID -e API_KEY_SECRET=$API_KEY_SECRET privmx-bridge pmxbridge_cli "$@"
