#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DOCKER_COMPOSE_OVERRIDE=$DIR/docker-compose.override.yaml
VOLUMES_DIR=$DIR/volumes

INFRA_ENV_FILE=$DIR/streams.env
BRIDGE_ENV_FILE=$DIR/bridge.env

CREATE_SOLUTION=true
CREATE_CONTEXT=true
DB_URL=""
NETWORK_NAME="privmx-infra-network"

WITH_JANUS=false
MODE="DEV"
FLAG_JANUS_SET=false
FLAG_PROD_SET=false

USE_LOCAL_JANUS=true
USE_LOCAL_COTURN=true
EXT_JANUS_HOST=""
EXT_JANUS_PORT=""
EXT_JANUS_SECRET=""
EXT_COTURN_URL=""
EXT_COTURN_SECRET=""

mkdir -p "$VOLUMES_DIR"

for file in "$INFRA_ENV_FILE" "$BRIDGE_ENV_FILE"; do
    if [ ! -f "$file" ]; then
        touch "$file" 2>/dev/null || { echo "Cannot create $file"; exit 1; }
    fi
    if [ ! -r "$file" ]; then
        echo "Cannot read $file"
        exit 1
    fi
done

source "$INFRA_ENV_FILE"
source "$BRIDGE_ENV_FILE"

ask_confirm() {
    local prompt="$1"
    local default="$2"
    local reply

    printf "\e[1;33m$prompt\e[0m "
    if [ "$default" = "y" ]; then
        printf "[Y/n] "
    else
        printf "[y/N] "
    fi
    
    read reply
    if [ -z "$reply" ]; then reply=$default; fi

    case "$reply" in
        Y*|y*) return 0 ;;
        *) return 1 ;;
    esac
}

get_public_ip() {
    if command -v dig >/dev/null 2>&1; then
        dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"'
    fi
}

get_local_ip() {
    local ip=""
    if command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
    fi
    echo "$ip"
}

update_env_var() {
    local key=$1
    local val=$2
    local file=$3
    
    if grep -q "^${key}=" "$file"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i "" "s|^${key}=.*|${key}=${val}|" "$file"
        else
            sed -i "s|^${key}=.*|${key}=${val}|" "$file"
        fi
    else
        if [ -s "$file" ] && [ "$(tail -c1 "$file" | wc -l)" -eq 0 ]; then
            echo "" >> "$file"
        fi
        printf "${key}=${val}\n" >> "$file"
    fi
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --no-solution) CREATE_SOLUTION=false ;;
        --no-context) CREATE_CONTEXT=false ;;
        --db-url) DB_URL="$2"; shift ;;
        --with-janus) 
            WITH_JANUS=true 
            FLAG_JANUS_SET=true
            ;;
        --external-janus)
            USE_LOCAL_JANUS=false
            WITH_JANUS=true
            FLAG_JANUS_SET=true
            ;;
        --external-coturn)
            USE_LOCAL_COTURN=false
            WITH_JANUS=true
            FLAG_JANUS_SET=true
            ;;
        --prod) 
            MODE="PROD" 
            FLAG_PROD_SET=true
            ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done


printf "***************************************************************************\n"
printf "*                                                                         *\n"
printf "*                         \e[1;36mPRIVMX BRIDGE INSTALLER\e[0m                         *\n"
printf "*                                                                         *\n"
printf "***************************************************************************\n"
printf "\n"

# ==========================================
# INTERACTIVE SETUP
# ==========================================

if [ "$FLAG_JANUS_SET" = false ]; then
    if ask_confirm "Do you want to setup Janus Gateway (WebRTC video/audio support)?" "n"; then
        WITH_JANUS=true
    else
        WITH_JANUS=false
    fi
fi

if [ "$WITH_JANUS" = true ]; then

    if [ "$USE_LOCAL_JANUS" = true ]; then
        if ask_confirm "Do you want to use an EXTERNAL Media Server (Janus) instead of hosting locally?" "n"; then
            USE_LOCAL_JANUS=false
        fi
    fi

    if [ "$USE_LOCAL_JANUS" = false ]; then
        printf "  \e[1;36mEnter External Janus Host\e[0m (e.g., media.example.com): "
        read EXT_JANUS_HOST
        printf "  \e[1;36mEnter External Janus Port\e[0m (e.g., 8989): "
        read EXT_JANUS_PORT
        printf "  \e[1;36mEnter External Janus API Secret\e[0m: "
        read EXT_JANUS_SECRET
    fi

    if [ "$USE_LOCAL_COTURN" = true ]; then
        if ask_confirm "Do you want to use an EXTERNAL TURN Server (coTURN) instead of hosting locally?" "n"; then
            USE_LOCAL_COTURN=false
        fi
    fi

    if [ "$USE_LOCAL_COTURN" = false ]; then
        printf "  \e[1;36mEnter External TURN URL\e[0m (e.g., turn:turn.example.com:3478): "
        read EXT_COTURN_URL
        printf "  \e[1;36mEnter External TURN Secret\e[0m: "
        read EXT_COTURN_SECRET
    fi

    if [ "$USE_LOCAL_JANUS" = true ] || [ "$USE_LOCAL_COTURN" = true ]; then
        if [ "$FLAG_PROD_SET" = false ]; then
            printf "\n"
            printf "\e[1;33mSelect Media Services Mode:\e[0m\n"
            printf "\n"
            printf "  \e[1;32mDEV Mode (Recommended for local development)\e[0m\n"
            printf "    - Limited port range (~300 ports) due to Docker limitations\n"
            printf "    - Uses Docker bridge network with port forwarding\n"
            printf "    - Fast startup, suitable for testing on single machine\n"
            printf "    - May have issues with many concurrent WebRTC connections\n"
            printf "\n"
            printf "  \e[1;33mPROD Mode (Required for public/production servers)\e[0m\n"
            printf "    - Uses Docker host network mode (bypasses port forwarding)\n"
            printf "    - Full port range available for WebRTC (10000-65535)\n"
            printf "    - Required for servers exposed to the internet\n"
            printf "    - Supports many concurrent video/audio connections\n"
            printf "\n"
            if ask_confirm "Do you want to configure for PRODUCTION (public server)?" "n"; then
                MODE="PROD"
            else
                MODE="DEV"
            fi
            printf "\n"
        fi
        
        printf "\e[1;33mSelect the IP address to use for local Media/TURN configuration:\e[0m\n"
        
        PUB_IP=$(get_public_ip)
        LOC_IP=$(get_local_ip)
        LOCALHOST="127.0.0.1"
        
        [ -z "$PUB_IP" ] && PUB_IP_DISPLAY="Not Detected" || PUB_IP_DISPLAY="$PUB_IP"
        [ -z "$LOC_IP" ] && LOC_IP_DISPLAY="Not Detected" || LOC_IP_DISPLAY="$LOC_IP"

        printf "  \e[1;36m1)\e[0m Public IP:        \e[1;37m$PUB_IP_DISPLAY\e[0m\n"
        printf "  \e[1;36m2)\e[0m Local Network IP: \e[1;37m$LOC_IP_DISPLAY\e[0m\n"
        printf "  \e[1;36m3)\e[0m Localhost:        \e[1;37m$LOCALHOST\e[0m\n"
        printf "  \e[1;36m4)\e[0m Custom Input\n"
        printf "\n"
        printf "  Enter number [1-4]: "
        read IP_CHOICE

        case $IP_CHOICE in
            1) CURRENT_IP=${PUB_IP:-$LOCALHOST} ;;
            2) CURRENT_IP=${LOC_IP:-$LOCALHOST} ;;
            3) CURRENT_IP=$LOCALHOST ;;
            4)
                printf "  Enter IP address: "
                read MAN_IP
                CURRENT_IP=${MAN_IP:-$LOCALHOST}
                ;;
            *) CURRENT_IP=$LOCALHOST ;;
        esac
        printf "  \e[1;32mSelected IP: $CURRENT_IP\e[0m\n\n"
    else
        CURRENT_IP="127.0.0.1"
    fi
fi


if ! docker network ls | grep -q $NETWORK_NAME; then
    echo "Creating docker network: $NETWORK_NAME"
    docker network create $NETWORK_NAME
fi

COMPOSE_FILES=("-f" "docker-compose.yaml")

# ==========================================
# LOCAL MEDIA COMPONENT DEPLOYMENT
# ==========================================

if [ "$WITH_JANUS" = true ] && { [ "$USE_LOCAL_JANUS" = true ] || [ "$USE_LOCAL_COTURN" = true ]; }; then
    
    OS="$(uname -s)"

    safe_sed() {
        local pattern=$1
        local file=$2
        if [ ! -f "$file" ]; then return; fi
        if [ "$OS" = "Darwin" ]; then
            sed -i "" "$pattern" "$file"
        else
            sed -i "$pattern" "$file"
        fi
    }

    if [[ "$MODE" == "PROD" ]]; then
        J_RANGE="10000-49000"
        T_MIN="49152"
        T_MAX="65535"
        echo "Configuring Local Media Services for PRODUCTION..."
    else
        J_RANGE="10000-10299"
        T_MIN="20000"
        T_MAX="20200"
        echo "Configuring Local Media Services for DEVELOPMENT..."
    fi

    JANUS_CONF_DIR="$VOLUMES_DIR/janus-conf"
    CERTS_DIR="$VOLUMES_DIR/certs"
    RECORDINGS_DIR="$VOLUMES_DIR/recordings"
    COTURN_CONF_DIR="$VOLUMES_DIR/coturn"
    COTURN_CONF_FILE="$COTURN_CONF_DIR/turnserver.conf"

    mkdir -p "$JANUS_CONF_DIR" "$CERTS_DIR" "$RECORDINGS_DIR" "$COTURN_CONF_DIR"
    chmod 777 "$RECORDINGS_DIR" 2>/dev/null

    if [ -z "$(ls -A "$JANUS_CONF_DIR" 2>/dev/null)" ]; then
        docker run --rm -v "$JANUS_CONF_DIR":/tmp/conf simplito/janus-gateway-docker:v1.4.0 sh -c "cp /usr/local/etc/janus/*.jcfg /tmp/conf/"
    fi

    update_env_var "PUBLIC_IP" "$CURRENT_IP" "$INFRA_ENV_FILE"

    CURRENT_TURN_SECRET=$(grep TURN_SHARED_SECRET "$INFRA_ENV_FILE" | cut -d '=' -f2)
    if [[ -z "$CURRENT_TURN_SECRET" ]]; then
        CURRENT_TURN_SECRET=$(openssl rand -hex 16)
        update_env_var "TURN_SHARED_SECRET" "$CURRENT_TURN_SECRET" "$INFRA_ENV_FILE"
    fi
    
    CURRENT_JANUS_SECRET=$(grep JANUS_API_SECRET "$INFRA_ENV_FILE" | cut -d '=' -f2)
    if [[ -z "$CURRENT_JANUS_SECRET" ]]; then
        CURRENT_JANUS_SECRET=$(openssl rand -hex 16)
        update_env_var "JANUS_API_SECRET" "$CURRENT_JANUS_SECRET" "$INFRA_ENV_FILE"
    fi

    CURRENT_JANUS_ADMIN_SECRET=$(grep JANUS_ADMIN_SECRET "$INFRA_ENV_FILE" | cut -d '=' -f2)
    if [[ -z "$CURRENT_JANUS_ADMIN_SECRET" ]]; then
        CURRENT_JANUS_ADMIN_SECRET=$(openssl rand -base64 32)
        update_env_var "JANUS_ADMIN_SECRET" "$CURRENT_JANUS_ADMIN_SECRET" "$INFRA_ENV_FILE"
    fi


    safe_sed_escape() {
        printf '%s' "$1" | sed 's/&/\\&/g'
    }

    JANUS_IP=$CURRENT_IP
    TURN_IP=$CURRENT_IP 

    ESCAPED_JANUS_SECRET=$(safe_sed_escape "$CURRENT_JANUS_SECRET")
    ESCAPED_ADMIN_SECRET=$(safe_sed_escape "$CURRENT_JANUS_ADMIN_SECRET")


    safe_sed "s/^[[:space:]]*[#;]*[[:space:]]*rtp_port_range[[:space:]]*=.*/     rtp_port_range = \"$J_RANGE\"/" "$JANUS_CONF_DIR/janus.jcfg"
    safe_sed "s/^[[:space:]]*[#;]*[[:space:]]*nat_1_1_mapping[[:space:]]*=.*/    nat_1_1_mapping = \"$JANUS_IP\"/" "$JANUS_CONF_DIR/janus.jcfg"
    
    safe_sed "s|^[[:space:]]*[#;]*[[:space:]]*api_secret[[:space:]]*=.*|    api_secret = \"$ESCAPED_JANUS_SECRET\"|" "$JANUS_CONF_DIR/janus.jcfg"
    safe_sed "s|^[[:space:]]*[#;]*[[:space:]]*admin_secret[[:space:]]*=.*|    admin_secret = \"$ESCAPED_ADMIN_SECRET\"|" "$JANUS_CONF_DIR/janus.jcfg"

    safe_sed "s|^[[:space:]]*[#;]*[[:space:]]*https[[:space:]]*=.*|    https = true|" "$JANUS_CONF_DIR/janus.transport.http.jcfg"
    safe_sed "s|^[[:space:]]*[#;]*[[:space:]]*secure_port[[:space:]]*=.*|    secure_port = 8089|" "$JANUS_CONF_DIR/janus.transport.http.jcfg"

    safe_sed "s|^[[:space:]]*[#;]*[[:space:]]*wss[[:space:]]*=.*|    wss = true|" "$JANUS_CONF_DIR/janus.transport.websockets.jcfg"
    safe_sed "s|^[[:space:]]*[#;]*[[:space:]]*wss_port[[:space:]]*=.*|    wss_port = 8989|" "$JANUS_CONF_DIR/janus.transport.websockets.jcfg"

    CERT_DIR="/usr/local/share/janus/certs"
    PEM_FILE="$CERT_DIR/mycert.pem"
    KEY_FILE="$CERT_DIR/mycert.key"

    if [ ! -f "$CERTS_DIR/mycert.pem" ]; then
        openssl req -x509 -newkey rsa:4096 -keyout "$CERTS_DIR/mycert.key" -out "$CERTS_DIR/mycert.pem" -days 365 -nodes -subj "/CN=JanusWebRTC" 2>/dev/null
    fi

    safe_sed "s|.*cert_pem =.*|cert_pem = \"$PEM_FILE\"|" "$JANUS_CONF_DIR/janus.jcfg"
    safe_sed "s|.*cert_key =.*|cert_key = \"$KEY_FILE\"|" "$JANUS_CONF_DIR/janus.jcfg"
    safe_sed "s|.*cert_pem =.*|cert_pem = \"$PEM_FILE\"|" "$JANUS_CONF_DIR/janus.transport.http.jcfg"
    safe_sed "s|.*cert_key =.*|cert_key = \"$KEY_FILE\"|" "$JANUS_CONF_DIR/janus.transport.http.jcfg"
    safe_sed "s|.*cert_pem =.*|cert_pem = \"$PEM_FILE\"|" "$JANUS_CONF_DIR/janus.transport.websockets.jcfg"
    safe_sed "s|.*cert_key =.*|cert_key = \"$KEY_FILE\"|" "$JANUS_CONF_DIR/janus.transport.websockets.jcfg"

    if [ "$USE_LOCAL_COTURN" = true ]; then
        DOMAIN_VALUE=${CURRENT_IP:-127.0.0.1}
        
        cat > "$COTURN_CONF_FILE" << EOF
external-ip=$TURN_IP

realm=$DOMAIN_VALUE
domain=$DOMAIN_VALUE

use-auth-secret
static-auth-secret=$CURRENT_TURN_SECRET

listening-port=3478
tls-listening-port=5349

fingerprint
no-cli
no-multicast-peers
no-loopback-peers

min-port=$TURN_MIN_PORT
max-port=$TURN_MAX_PORT

verbose
EOF
    fi

    if [[ "$MODE" == "PROD" ]]; then
        HOST_NETWORK_OVERRIDE=$DIR/docker-compose.janus.host.yaml
        COMPOSE_FILES+=("-f" "$HOST_NETWORK_OVERRIDE")
    else
        COMPOSE_FILES+=("-f" "docker-compose.janus.yaml")
    fi
fi


# ==========================================
# ENV FILE FINALIZATION (bridge.env)
# ==========================================

if [ "$WITH_JANUS" = true ]; then
    update_env_var "PMX_STREAM_ENABLED" "true" "$BRIDGE_ENV_FILE"
    update_env_var "PMX_MEDIA_SERVER_ALLOW_SELF_SIGNED_CERTS" "true" "$BRIDGE_ENV_FILE"

    if [ "$USE_LOCAL_JANUS" = true ]; then
        update_env_var "PMX_STREAMS_MEDIA_SERVER" "mediaserver" "$BRIDGE_ENV_FILE"
        update_env_var "PMX_STREAMS_MEDIA_SERVER_PORT" "8989" "$BRIDGE_ENV_FILE"
        update_env_var "PMX_STREAMS_MEDIA_SERVER_SECRET" "$CURRENT_JANUS_SECRET" "$BRIDGE_ENV_FILE"
    else
        update_env_var "PMX_STREAMS_MEDIA_SERVER" "$EXT_JANUS_HOST" "$BRIDGE_ENV_FILE"
        update_env_var "PMX_STREAMS_MEDIA_SERVER_PORT" "$EXT_JANUS_PORT" "$BRIDGE_ENV_FILE"
        update_env_var "PMX_STREAMS_MEDIA_SERVER_SECRET" "$EXT_JANUS_SECRET" "$BRIDGE_ENV_FILE"
    fi

    if [ "$USE_LOCAL_COTURN" = true ]; then
        update_env_var "PMX_STREAMS_TURN_SERVER" "turn:$TURN_IP:3478" "$BRIDGE_ENV_FILE"
        update_env_var "PMX_STREAMS_TURN_SERVER_SECRET" "$CURRENT_TURN_SECRET" "$BRIDGE_ENV_FILE"
    else
        update_env_var "PMX_STREAMS_TURN_SERVER" "$EXT_COTURN_URL" "$BRIDGE_ENV_FILE"
        update_env_var "PMX_STREAMS_TURN_SERVER_SECRET" "$EXT_COTURN_SECRET" "$BRIDGE_ENV_FILE"
    fi
else
    update_env_var "PMX_STREAM_ENABLED" "false" "$BRIDGE_ENV_FILE"
fi


# ==========================================
# DATABASE OVERRIDE & COMPOSE BOOT
# ==========================================

if [ -n "$DB_URL" ]; then
    printf "services:\n  mongodb: !reset\n  privmx-bridge:\n    environment:\n      PRIVMX_MONGO_URL: $DB_URL\n    depends_on: !reset\n" > "$DOCKER_COMPOSE_OVERRIDE"
    COMPOSE_FILES+=("-f" "$DOCKER_COMPOSE_OVERRIDE")
fi

update_env_var "CURRENT_IP" "${CURRENT_IP:-127.0.0.1}" "$INFRA_ENV_FILE"
update_env_var "DOMAIN" "${CURRENT_IP:-127.0.0.1}" "$INFRA_ENV_FILE"

printf "\e[1;36m-----------------\nBooting up\n-----------------\e[0m\n"
cd $DIR

docker compose "${COMPOSE_FILES[@]}" --env-file "$INFRA_ENV_FILE" --env-file "$BRIDGE_ENV_FILE" up -d --wait
printf "OK\n"
printf "\n"

printf "\e[1;36m-----------------\nPreparing data\n-----------------\e[0m\n"

if [ -z $API_KEY_ID ] || [ -z $API_KEY_SECRET ]; then
    printf "Creating API key... "
    DATA=$(docker compose "${COMPOSE_FILES[@]}" --env-file "$INFRA_ENV_FILE" --env-file "$BRIDGE_ENV_FILE" exec -T privmx-bridge pmxbridge_createapikey)
    eval "$DATA"
    update_env_var "API_KEY_ID" "$API_KEY_ID" "$BRIDGE_ENV_FILE"
    update_env_var "API_KEY_SECRET" "$API_KEY_SECRET" "$BRIDGE_ENV_FILE"
    printf "\033[0;32mOK\033[0m\n"
else
    printf "API key already created \033[0;32mOK\033[0m\n"
fi

if [ -z $SOLUTION_ID ]; then
    if [ $CREATE_SOLUTION == "true" ]; then
        printf "Creating solution... "
        SOLUTION_ID=$(docker compose "${COMPOSE_FILES[@]}" --env-file "$INFRA_ENV_FILE" --env-file "$BRIDGE_ENV_FILE" exec -T -e API_KEY_ID=$API_KEY_ID -e API_KEY_SECRET=$API_KEY_SECRET privmx-bridge pmxbridge_cli solution/createSolution "{\"name\": \"Main\"}" --json=.result.solutionId -r)
        update_env_var "SOLUTION_ID" "$SOLUTION_ID" "$BRIDGE_ENV_FILE"
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
        CONTEXT_ID=$(docker compose "${COMPOSE_FILES[@]}" --env-file "$INFRA_ENV_FILE" --env-file "$BRIDGE_ENV_FILE" exec -T -e API_KEY_ID=$API_KEY_ID -e API_KEY_SECRET=$API_KEY_SECRET privmx-bridge pmxbridge_cli context/createContext "{\"name\": \"MainContext\", \"solution\": \"$SOLUTION_ID\", \"description\": \"\", \"scope\": \"private\"}" --json=.result.contextId -r)
        update_env_var "CONTEXT_ID" "$CONTEXT_ID" "$BRIDGE_ENV_FILE"
        printf "\033[0;32mOK\033[0m\n"
    else
        printf "Skipping context creation \033[0;32mOK\033[0m\n"
    fi
else
    printf "Context already created \033[0;32mOK\033[0m\n"
fi

PUBLIC_KEY=$(docker compose "${COMPOSE_FILES[@]}" --env-file "$INFRA_ENV_FILE" --env-file "$BRIDGE_ENV_FILE" exec -T privmx-bridge pmxbridge_getpublickey --kvprint | grep 'PUBLIC_KEY=' | cut -d= -f2)

sleep 1

printf "\n"
printf "  \e[1;32m______     _      ___  _____   __\e[0m\n"
printf "  \e[1;32m| ___ \   (_)     |  \/  |\ \ / /\e[0m\n"
printf "  \e[1;32m| |_/ / __ ___   _| .  . | \ V / \e[0m\n"
printf "  \e[1;32m|  __/ '__| \ \ / / |\/| | /   \ \e[0m     \e[1;36mPrivMX Bridge Installed!\e[0m\n"
printf "  \e[1;32m| |  | |  | |\ V /| |  | |/ /^\ \ \e[0m\n"
printf "  \e[1;32m\_|  |_|  |_| \_/ \_|  |_/\/   \/\e[0m\n"
printf "\n"

printf "  \e[1;97mBridge Url:\e[0m    \e[1;32mhttp://localhost:9111\e[0m\n"
printf "  \e[1;97mAPI Key:\e[0m       \e[1;32m$API_KEY_ID\e[0m\n"
printf "  \e[1;97mAPI Secret:\e[0m    \e[1;32m$API_KEY_SECRET\e[0m\n"
printf "  \e[1;97mPublic Key:\e[0m    \e[1;32m$PUBLIC_KEY\e[0m\n"

if [ -n "$SOLUTION_ID" ]; then
    printf "\n  \e[1;97mSolution:\e[0m      \e[1;32m$SOLUTION_ID\e[0m\n"
    [ -n "$CONTEXT_ID" ] && printf "  \e[1;97mContext:\e[0m       \e[1;32m$CONTEXT_ID\e[0m\n"
fi

if [ "$WITH_JANUS" = true ]; then
    printf "\n  \e[1;97mMedia Server (Janus)\e[0m\n"
    if [ "$USE_LOCAL_JANUS" = true ]; then
        printf "     \e[1;90mWSS:\e[0m    \e[1;32mwss://$CURRENT_IP:8989\e[0m\n"
        printf "     \e[1;90mHTTPS:\e[0m  \e[1;32mhttps://$CURRENT_IP:8089\e[0m\n"
        printf "     \e[1;90mRTP:\e[0m    \e[1;32m$J_RANGE/udp\e[0m\n"
        printf "     \e[1;90mSecret:\e[0m \e[1;32m$CURRENT_JANUS_SECRET\e[0m\n"
        printf "     \e[1;90mAdmin:\e[0m  \e[1;32m$CURRENT_JANUS_ADMIN_SECRET\e[0m\n"
    else
        printf "     \e[1;90mHost:\e[0m   \e[1;32m$EXT_JANUS_HOST:$EXT_JANUS_PORT\e[0m\n"
        printf "     \e[1;90mSecret:\e[0m \e[1;32m$EXT_JANUS_SECRET\e[0m\n"
    fi
    printf "\n  \e[1;97mTURN Server (Coturn)\e[0m\n"
    if [ "$USE_LOCAL_COTURN" = true ]; then
        printf "     \e[1;90mURL:\e[0m    \e[1;32mturn:$CURRENT_IP:3478\e[0m\n"
        printf "     \e[1;90mSecret:\e[0m \e[1;32m$CURRENT_TURN_SECRET\e[0m\n"
    else
        printf "     \e[1;90mURL:\e[0m  \e[1;32m$EXT_COTURN_URL\e[0m\n"
        printf "     \e[1;90mSecret:\e[0m \e[1;32m$EXT_COTURN_SECRET\e[0m\n"
    fi
fi

printf "\n  \e[1;97mConfig:\e[0m  streams.env, bridge.env\n"
printf "  \e[1;97mDocs:\e[0m   \e[1;32mhttps://docs.privmx.dev\e[0m\n"

if [ "$WITH_JANUS" = "true" ] && [ "$USE_LOCAL_JANUS" = "true" ]; then
    printf "\n \e[1;33m [WARN] Self-signed certificates in ./volumes/certs/\e[0m\n"
    printf "  \e[1;90m   Set PMX_MEDIA_SERVER_ALLOW_SELF_SIGNED_CERTS=false after replacing.\e[0m\n"
fi

if [ "$WITH_JANUS" = "true" ] && [ "$USE_LOCAL_COTURN" = "true" ]; then
    printf "\n \e[1;33m [WARN] Configure TLS certificates for TURN in ./volumes/coturn/turnserver.conf\e[0m\n"
    printf "  \e[1;90m   Add cert and pkey paths for production use.\e[0m\n"
fi

if [ "$WITH_JANUS" = "true" ] && { [ "$USE_LOCAL_JANUS" = "true" ] || [ "$USE_LOCAL_COTURN" = "true" ]; }; then
    printf "\n"
    if [[ "$MODE" == "PROD" ]]; then
        printf "  \e[1;32mPROD mode:\e[0m  host network, Janus: 10000-49000, TURN: 49152-65535\n"
    else
        printf "  \e[1;33mDEV mode:\e[0m  ~300 ports (Docker limit). Use PROD for public servers.\n"
    fi
fi

printf "\n"