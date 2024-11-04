#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
VOLUMES_DIR=$DIR/volumes
ENV_FILE=$VOLUMES_DIR/.env

if [ -f $ENV_FILE ]; then
    source $ENV_FILE
fi

insert_variable() {
    KEY=$1
    VALUE=$2
    
    printf "$KEY=$VALUE\n" >> $ENV_FILE
}

if [ -z $API_KEY_ID ] || [ -z $API_KEY_SECRET ]; then
    printf "Creating API key... "
    cd $DIR
    DATA=$(docker compose exec -T privmx-bridge pmxbridge_createapikey)
    eval "$DATA"
    insert_variable API_KEY_ID $API_KEY_ID
    insert_variable API_KEY_SECRET $API_KEY_SECRET
    printf "\033[0;32mOK\033[0m\n"
else
    printf "API key already created \033[0;32mOK\033[0m\n"
fi

printf "           API Key ID:  $API_KEY_ID\n"
printf "       API Key Secret:  $API_KEY_SECRET\n"
