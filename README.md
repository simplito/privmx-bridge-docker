# PrivMX Bridge Docker

This repository provides a Docker Compose setup for PrivMX Bridge service along with its required dependencies.
It also includes MongoDB to provide a working PrivMX Bridge instance.
[PrivMX Bridge](https://github.com/simplito/privmx-bridge) is a secure, zero-knowledge server for encrypted data storage and communication.
It allows users to communicate and exchange data in a fully encrypted environment, ensuring end-to-end encryption and protecting data privacy at every step.

The PrivMX Bridge docker image is distributed for two platforms:
- linux/amd64
- linux/arm64/v8

## Setup

Clone the repository:

```
git clone https://github.com/simplito/privmx-bridge-docker.git
cd privmx-bridge-docker
```

## Quick start

It will boot up the containers, add the API key, one Solution, and one Context.

```
./setup.sh
```

**NOTE:** If you use Windows, run this command in Git Bash or a similar shell.

**NOTE:** If this script ends with containers in a waiting state, try running this script again.

**NOTE:** If you want to configure HTTPS [go to this section](#https).

**NOTE:** If you want to use external MongoDB [go to this section](#external-mongodb).

## Start

```
docker compose up -d
```

## Stop

```
docker compose down
```

## Logs

```
docker compose logs -f privmx-bridge
docker compose logs -f mongodb
```

## Update

To ensure you have the latest `privmx-bridge` image, always run the command below before executing the `docker compose up` command:

```
docker compose pull privmx-bridge
```

## Options of the setup script
If you don't want to create a Solution or Context, use the `--no-solution` or `--no-context` argument. If you pass the `--no-solution` argument, also no Context will be created, because it must be assigned to a Solution.

```
./setup.sh --no-solution
./setup.sh --no-context
```

### External MongoDB
You can use the `--db-url` argument to disable the included MongoDB container and instruct PrivMX Bridge to connect to a given database.
```
./setup.sh --db-url "YOUR_MONGODB_CONNECTION_STRING"
```
This command creates a `docker-compose.override.yaml` file. If you change your mind and want to use the included MongoDB, delete this file.

## Configuration

You can create a `bridge.env` file and put [environment variables](https://github.com/simplito/privmx-bridge#configuration-options) there.
Don't forget to bring down and bring up your setup to apply the changes:

```
docker compose down
docker compose up -d
```

## Create API Key

Run:

```
./createApiKey.sh
```

The API key allows you to fully manage your PrivMX Bridge. It is also saved in the `volumes/.env` file and will be used by the `cli.sh` script.

## Manage PrivMX Bridge

Run:

```
./cli.sh
```

To create a new Solution run:

```
./cli.sh solution/createSolution '{"name": "My New Solution"}'
```

To create a new Context run:

```
./cli.sh context/createContext '{"solution": "<solution-id-from-above>", "name": "MainContext", "description": "", "scope": "private"}'
```

## Documentation

Documentation for your PrivMX Bridge API is available at [http://localhost:9111/docs](http://localhost:9111/docs) or [https://bridge.privmx.dev](https://bridge.privmx.dev).

## Management panel

Management panel for your PrivMX Bridge is available at [http://localhost:9111/panel](http://localhost:9111/panel).

## Generate Key Pair

To generate a new ECC key pair, run:

```
./genKeyPair.sh
```

## HTTPS

The following example uses Nginx + Certbot method on Debian-based systems, but there are different ways to set up HTTPS.
First, set up your DNS so that `your.domain.com` points to your server.
Next, install Nginx and Certbot:

```
sudo apt-get update
sudo apt install certbot python3-certbot-nginx nginx
```

Then, open ports 80 and 443 on the firewall (this is outside the scope of this tutorial).
Next, add a virtual host by creating the `/etc/nginx/sites-available/your.domain.com` file with the following content:

```
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

Activate the virtual host:

```
sudo ln -s ../sites-available/your.domain.com /etc/nginx/sites-enabled/your.domain.com
```

Check the Nginx configuration:

```
nginx -t
```

Restart the Nginx:

```
sudo systemctl reload nginx
```

Retrieve a certificate using Certbot with the Nginx plugin:

```
sudo certbot --nginx -d your.domain.com
```

Test the renewal process:

```
sudo certbot renew --dry-run
```

# System Requirements

System requirements for PrivMX Bridge itself:
- 1 CPU
- 512 MB RAM

Note that this Docker Compose setup also includes MongoDB. Go to
[MongoDB System Requirements](https://www.mongodb.com/docs/cloud-manager/tutorial/provisioning-prep/) to learn more.

# License

This software is licensed under the PrivMX Free License. PrivMX Bridge is also licensed under the PrivMX Free License.
