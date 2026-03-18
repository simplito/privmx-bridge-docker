# PrivMX Bridge Docker

This repository provides a Docker Compose setup for the PrivMX Bridge service along with its required dependencies, including MongoDB. [PrivMX Bridge](https://github.com/simplito/privmx-bridge) is a secure, zero-knowledge server for encrypted data storage and communication. It allows users to communicate and exchange data in a fully encrypted environment, ensuring end-to-end encryption and protecting data privacy at every step.

The PrivMX Bridge Docker image is distributed for two platforms:

* `linux/amd64`
* `linux/arm64/v8`

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Installation & Quick Start](#installation--quick-start)
   * [Setup Options](#setup-options)
   * [External MongoDB](#external-mongodb)
3. [Managing Services](#managing-services)
4. [Configuration](#configuration)
5. [Media Services Configuration (WebRTC)](#media-services-configuration-webrtc)
   * [Local Media Services](#local-media-services)
   * [External Media Services (Janus & coTURN)](#external-media-services-janus--coturn)
6. [CLI Tools & Management](#cli-tools--management)
   * [Create API Key](#create-api-key)
   * [Manage PrivMX Bridge](#manage-privmx-bridge)
   * [Generate Key Pair](#generate-key-pair)
   * [Management Panel](#management-panel)
7. [HTTPS Setup](#https-setup)
8. [Documentation](#documentation)
9. [License](#license)

## System Requirements

System requirements for PrivMX Bridge itself:

* 1 CPU
* 512 MB RAM

Note that this Docker Compose setup also includes MongoDB. Go to the [MongoDB Production Notes](https://www.mongodb.com/docs/cloud-manager/tutorial/provisioning-prep/) to learn more.

## Installation & Quick Start

Clone the repository to begin:

```bash
git clone https://github.com/simplito/privmx-bridge-docker.git
cd privmx-bridge-docker


```

To set up and run the PrivMX Bridge and chosen components:

```bash
./setup.sh


```

**Notes:**

* If using Windows, run this command in Git Bash or a similar shell.
* If the script ends with containers in a waiting state, try running the script again.
* If you want to configure HTTPS, see [HTTPS Setup](#https-setup).
* If you want to use an external database, see [External MongoDB](#external-mongodb).

### Setup Options

If you do not want to create a Solution or Context, use the `--no-solution` or `--no-context` arguments. Passing `--no-solution` will also skip Context creation, as a Context must be assigned to a Solution.

```bash
./setup.sh --no-solution
./setup.sh --no-context


```

### External MongoDB

You can use the `--db-url` argument to disable the included MongoDB container and instruct PrivMX Bridge to connect to an external database.

```bash
./setup.sh --db-url "YOUR_MONGODB_CONNECTION_STRING"


```

This command creates a `docker-compose.override.yaml` file. If you decide to revert to the included MongoDB, delete this override file.

## Managing Services

### Quick Start

Start Bridge and MongoDB only:

```bash
docker compose up -d
```

### With Local Media Services (Janus + coTURN)

The setup script automatically selects the appropriate compose file based on your mode:

- **`docker-compose.janus.yaml`** (DEV mode): Uses Docker bridge network with port forwarding. Limited port range (~300 ports). Suitable for local development.

- **`docker-compose.janus.host.yaml`** (PROD mode): Uses Docker host network mode. Full port range (10000-65535). Required for production/public servers.

> **Note:** The `./setup.sh` script automatically selects the correct compose file based on DEV/PROD mode.

Start with media services:

```bash
# DEV mode
docker compose -f docker-compose.yaml -f docker-compose.janus.yaml up -d

# PROD mode
docker compose -f docker-compose.yaml -f docker-compose.janus.host.yaml up -d
```

### Stop

```bash
# Basic (Bridge + MongoDB only)
docker compose down

# With media services - use the same compose files as when starting:
docker compose -f docker-compose.yaml -f docker-compose.janus.yaml down
# or
docker compose -f docker-compose.yaml -f docker-compose.janus.host.yaml down
```

### Logs

```bash
# Basic services
docker compose logs -f privmx-bridge
docker compose logs -f mongodb

# Media services (use the same compose files as when starting):
docker compose -f docker-compose.yaml -f docker-compose.janus.yaml logs -f mediaserver
docker compose -f docker-compose.yaml -f docker-compose.janus.yaml logs -f coturn
```

### Update

Pull the latest image before restarting:

```bash
docker compose pull privmx-bridge
docker compose up -d
```

## Configuration

You can create a `bridge.env` file and put your environment variables there. Ensure you restart your setup to apply the changes:

```bash
docker compose down
docker compose up -d


```

## Media Services Configuration (WebRTC)

When running `./setup.sh --with-media` (or answering "yes" during the interactive prompt), the script configures WebRTC video and audio support.

### Local Media Services

By default, the script sets up local Docker containers for Janus and coTURN. The script will:

1. Create `janus-conf`, `certs`, and `recordings` directories.
2. Download default Janus configurations.
3. Generate self-signed SSL certificates.
4. Patch Janus configuration files to use the generated certificates and configured RTP ports.
5. Set up a shared Docker network.

The local Janus Gateway and coTURN Server are defined in `docker-compose.janus.yaml`.

### External Media Services (Janus & coTURN)

For production environments, these services can be hosted on dedicated external servers.

#### Order of Operations

Services must be provisioned in the following order:

1. **coTURN**: Establish the relay server, apply certificates, and generate the Shared Secret.
2. **Janus**: Configure media routing, certificates, and plugins.
3. **PrivMX Bridge**: Connect the Bridge to the external services.

#### Step 1: Deploy External coTURN

coTURN acts as the STUN/TURN relay for WebRTC traffic. It must be accessible via the public internet.

**1. Generate a Shared Secret**
Generate a cryptographic string to secure the TURN server. Retain this value.

```bash
openssl rand -hex 16


```

**2. Configure SSL/TLS Certificates**
To support secure WebRTC connections (TURNS over TLS), your coTURN server must be configured with valid SSL/TLS certificates (e.g., Let's Encrypt). Ensure your certificate and private key are mounted and referenced in your coTURN configuration.

**3. Deploy coTURN**

Create a `turnserver.conf` file:

```
external-ip=YOUR_PUBLIC_IP

realm=your.domain.com
domain=your.domain.com

use-auth-secret
static-auth-secret=YOUR_SHARED_SECRET

listening-port=3478
tls-listening-port=5349

# TLS certificates (replace with your cert paths)
cert=/path/to/cert.pem
pkey=/path/to/privkey.pem

fingerprint
no-cli
no-multicast-peers
no-loopback-peers

min-port=49152
max-port=65535

verbose
```

Create a `compose.yaml`:

```yaml
services:
  coturn:
    image: coturn/coturn:latest
    container_name: coturn-standalone
    network_mode: host
    volumes:
      - ./turnserver.conf:/etc/coturn/turnserver.conf:ro
      - ./cert.pem:/path/to/cert.pem:ro
      - ./privkey.pem:/path/to/privkey.pem:ro
    restart: unless-stopped
    command: -c /etc/coturn/turnserver.conf
```

Run with:

```bash
docker compose up -d
```

#### Step 2: Deploy External Janus

> **Note:** SSL certificates are required for Janus. Generate them using Let's Encrypt or create self-signed certificates before proceeding.

Create a `compose.yaml`:

```yaml
services:
  janus:
    image: simplito/janus-gateway-docker:v1.4.0
    container_name: janus-standalone
    network_mode: host
    volumes:
      - ./volumes/janus-conf:/usr/local/etc/janus
      - ./volumes/certs:/volumes/certs:ro
      - ./volumes/recordings:/recordings
    restart: unless-stopped
```

Run with:

```bash
docker compose up -d
```

Create the volumes directory and copy default Janus configuration:

```bash
docker run --rm -v ./volumes/janus-conf:/tmp/conf simplito/janus-gateway-docker:v1.4.0 sh -c "cp /usr/local/etc/janus/*.jcfg /tmp/conf/"
```

Configure the following files in `/volumes/janus-conf/`:

**1. `janus.jcfg`** - Core settings:

```ini
general: {
    api_secret = "YOUR_JANUS_API_SECRET"
    admin_secret = "YOUR_JANUS_ADMIN_SECRET"
}

nat: {
    nat_1_1_mapping = "YOUR_JANUS_PUBLIC_IP"
}

media: {
    rtp_port_range = "10000-49000"
}

certificates: {
    cert_pem = "/path/to/cert.pem"
    cert_key = "/path/to/privkey.pem"
}
```

**2. `janus.transport.http.jcfg`** - HTTP transport:

```ini
general: {
    https = true
    secure_port = 8089
    cert_pem = "/path/to/cert.pem"
    cert_key = "/path/to/privkey.pem"
}
```

**3. `janus.transport.websockets.jcfg`** - WebSocket transport:

```ini
general: {
    wss = true
    wss_port = 8989
    cert_pem = "/path/to/cert.pem"
    cert_key = "/path/to/privkey.pem"
}
```

**4. `janus.plugin.videoroom.jcfg`** - VideoRoom plugin:

```ini
general: {

}
```

Run with:

```bash
docker compose up -d
```

**Required Secrets:**
- `api_secret` - Used by PrivMX Bridge to connect to Janus
- `admin_secret` - Used for Janus admin API

**Firewall Requirements:** Allow TCP on ports 8089, 8989 and UDP on ports 10000-49000.

#### Step 3: Configure PrivMX Bridge

Run the installer script with the external service flags:

```bash
./setup.sh --external-janus --external-coturn


```

Provide the requested parameters when prompted (External Janus Host/Port, External TURN URL/Secret). The script will populate the `bridge.env` file and configure Bridge routing.

## CLI Tools & Management

### Create API Key

The API key allows you to fully manage your PrivMX Bridge. It is saved in the `volumes/.env` file and will be used by the `cli.sh` script.

```bash
./createApiKey.sh


```

### Manage PrivMX Bridge

Use the CLI tool to manage your instance:

```bash
./cli.sh


```

To create a new Solution:

```bash
./cli.sh solution/createSolution '{"name": "My New Solution"}'


```

To create a new Context:

```bash
./cli.sh context/createContext '{"solution": "<solution-id-from-above>", "name": "MainContext", "description": "", "scope": "private"}'


```

### Generate Key Pair

To generate a new ECC key pair:

```bash
./genKeyPair.sh


```

### Management Panel

The management panel for your PrivMX Bridge is available at [http://localhost:9111/panel](http://localhost:9111/panel).

## HTTPS Setup

The following example uses Nginx + Certbot on Debian-based systems. Ensure your DNS (`your.domain.com`) points to your server and ports 80 and 443 are open on your firewall.

**1. Install Dependencies**

```bash
sudo apt-get update
sudo apt-get install certbot python3-certbot-nginx nginx


```

**2. Configure Nginx Virtual Host**
Create `/etc/nginx/sites-available/your.domain.com`:

```nginx
server {
    listen 80;
    server_name your.domain.com;

    location / {
        proxy_pass http://localhost:9111;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
    }
}


```

**3. Activate and Restart Nginx**

```bash
sudo ln -s /etc/nginx/sites-available/your.domain.com /etc/nginx/sites-enabled/your.domain.com
sudo nginx -t
sudo systemctl reload nginx


```

**4. Retrieve Certificate**

```bash
sudo certbot --nginx -d your.domain.com


```

**5. Test Renewal**

```bash
sudo certbot renew --dry-run


```

## Documentation

Documentation for PrivMX Bridge API is available at [http://localhost:9111/docs](http://localhost:9111/docs) for your locally running instance or publicly at [https://bridge.privmx.dev](https://bridge.privmx.dev).

## License

This software is licensed under the PrivMX Free License. PrivMX Bridge is also licensed under the PrivMX Free License.