#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
VOLUMES_DIR=$DIR/volumes
ENV_FILE=$VOLUMES_DIR/.env
CREATE_SOLUTION=true
CREATE_CONTEXT=true

if [ -f $ENV_FILE ]; then
    source $ENV_FILE
fi

for ARG in "$@"; do
    if [ "$ARG" == "--no-solution" ]; then
        CREATE_SOLUTION=false
    fi
    if [ "$ARG" == "--no-context" ]; then
        CREATE_CONTEXT=false
    fi
done

insert_variable() {
    KEY=$1
    VALUE=$2
    
    printf "$KEY=$VALUE\n" >> $ENV_FILE
}

printf "***************************************************************************\n"
printf "*                                                                         *\n"
printf "*                         \e[1;36mPRIVMX BRIDGE INSTALLER\e[0m                         *\n"
printf "*                                                                         *\n"
printf "***************************************************************************\n"
printf "\n"

printf "\e[1;36m-----------------\nBooting up\n-----------------\e[0m\n"
cd $DIR
mkdir -p $VOLUMES_DIR
docker compose pull privmx-bridge
docker compose up -d --wait
printf "OK\n"
printf "\n"

printf "\e[1;36m-----------------\nPreparing data\n-----------------\e[0m\n"

if [ -z $API_KEY_ID ] || [ -z $API_KEY_SECRET ]; then
    printf "Creating API key... "
    DATA=$(docker compose exec -T privmx-bridge pmxbridge_createapikey)
    eval "$DATA"
    insert_variable API_KEY_ID $API_KEY_ID
    insert_variable API_KEY_SECRET $API_KEY_SECRET
    printf "\033[0;32mOK\033[0m\n"
else
    printf "API key already created \033[0;32mOK\033[0m\n"
fi

if [ -z $SOLUTION_ID ]; then
    if [ $CREATE_SOLUTION == "true" ]; then
        printf "Creating solution... "
        SOLUTION_ID=$(docker compose exec -T -e API_KEY_ID=$API_KEY_ID -e API_KEY_SECRET=$API_KEY_SECRET privmx-bridge pmxbridge_cli solution/createSolution "{\"name\": \"Main\"}" --json=.result.solutionId -r)
        insert_variable SOLUTION_ID $SOLUTION_ID
        printf "\033[0;32mOK\033[0m\n"
    else
        printf "Skipping solution creation \033[0;32mOK\033[0m\n"
    fi
else
    printf "Solution already created \033[0;32mOK\033[0m\n"
fi

if [ -z $CONTEXT_ID ]; then
    if [ $CREATE_SOLUTION == "true" ] && [ $CREATE_CONTEXT == "true" ]; then
        printf "Creating context... "
        CONTEXT_ID=$(docker compose exec -T -e API_KEY_ID=$API_KEY_ID -e API_KEY_SECRET=$API_KEY_SECRET privmx-bridge pmxbridge_cli context/createContext "{\"name\": \"MainContext\", \"solution\": \"$SOLUTION_ID\", \"description\": \"\", \"scope\": \"private\"}" --json=.result.contextId -r)
        insert_variable CONTEXT_ID $CONTEXT_ID
        printf "\033[0;32mOK\033[0m\n"
    else
        printf "Skipping context creation \033[0;32mOK\033[0m\n"
    fi
else
    printf "Context already created \033[0;32mOK\033[0m\n"
fi

sleep 1

printf "\n"
printf "***************************************************************************\n"
printf "*                                                                         *\n"
printf "*\e[1;32m     _____      _       __  ____   __  ____       _     _                \e[0m*\n"
printf "*\e[1;32m    |  __ \    (_)     |  \/  \ \ / / |  _ \     (_)   | |               \e[0m*\n"
printf "*\e[1;32m    | |__) | __ ___   _| \  / |\ V /  | |_) |_ __ _  __| | __ _  ___     \e[0m*\n"
printf "*\e[1;32m    |  ___/ '__| \ \ / / |\/| | > <   |  _ <| '__| |/ _\` |/ _\` |/ _ \\    \e[0m*\n"
printf "*\e[1;32m    | |   | |  | |\ V /| |  | |/ . \  | |_) | |  | | (_| | (_| |  __/    \e[0m*\n"
printf "*\e[1;32m    |_|   |_|  |_| \_/ |_|  |_/_/ \_\ |____/|_|  |_|\__,_|\__, |\___|    \e[0m*\n"
printf "*\e[1;32m                                                           __/ |         \e[0m*\n"
printf "*\e[1;32m                                                          |___/          \e[0m*\n"
printf "*                                                                         *\n"
printf "*            \e[1;32mInstallation Complete! Thank you for choosing us :)\e[0m          *\n"
printf "*                                                                         *\n"
printf "***************************************************************************\n"
printf "\n"
printf "    PrivMX Bridge URL:  http://localhost:9111\n"
printf "\n"
printf "           API Key ID:  $API_KEY_ID\n"
printf "       API Key Secret:  $API_KEY_SECRET\n"

if [ -n "$SOLUTION_ID" ]; then
    printf "\n"
    printf "    IDs generated for your application:\n"
    printf "          Solution ID:  $SOLUTION_ID\n"
    
    if [ -n "$CONTEXT_ID" ]; then
        printf "           Context ID:  $CONTEXT_ID\n"
    fi
fi
printf "\n"
printf "All the data above is saved in the ./volumes/.env file.\n"
printf "To learn what you can do with PrivMX Bridge, visit https://docs.privmx.dev/bridge/getting-started#after-installing\n"
