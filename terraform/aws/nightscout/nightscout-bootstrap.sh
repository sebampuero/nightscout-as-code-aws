#!/bin/bash

echo "Configuring the instance environment"
export NS-API-KEY="${var.api_key}"
export NS-DOMAIN="${var.domain}"
export NS-FEATURES="${var.features}"

echo "Updating the system and installing Docker CE"
apt install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install docker-ce

echo "Setting up nightscout"
mkdir /nightscout
cat > /nightscout/docker-compose.yml <<EOD
# This is a modified version of the Nightscout Project's own Docker Compose file
# https://github.com/nightscout/cgm-remote-monitor/blob/master/docker-compose.yml
# traefik has been removed because this project uses Caddy and Caddy Docker Proxy

version: '3.7'

services:
  caddy:
    image: lucaslorentz/caddy-docker-proxy:ci-alpine
    ports:
      - 80:80
      - 443:443
    environment:
      - CADDY_INGRESS_NETWORKS=caddy
    networks:
      - caddy
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - caddy_data:/data
    restart: unless-stopped

  mongo:
    image: mongo:4.4
    networks:
      - caddy
    volumes:
      - ${NS_MONGO_DATA_DIR:-./mongo-data}:/data/db:cached

  nightscout:
    image: nightscout/cgm-remote-monitor:latest
    networks:
      - caddy
    labels:
      caddy: ${NS-DOMAIN}
      caddy.reverse_proxy: "{{upstreams 1337}}"
    container_name: nightscout
    restart: always
    depends_on:
      - mongo
    # labels:
    #   - 'traefik.enable=true'
    #   # Change the below Host from `localhost` to be the web address where Nightscout is running.
    #   # Also change the email address in the `traefik` service below.
    #   - 'traefik.http.routers.nightscout.rule=Host(`localhost`)'
    #   - 'traefik.http.routers.nightscout.entrypoints=websecure'
    #   - 'traefik.http.routers.nightscout.tls.certresolver=le'
    environment:
      ### Variables for the container
      NODE_ENV: production
      TZ: Etc/UTC

      ### Overridden variables for Docker Compose setup
      # The `nightscout` service can use HTTP, because we use `traefik` to serve the HTTPS
      # and manage TLS certificates
      INSECURE_USE_HTTP: 'true'

      # For all other settings, please refer to the Environment section of the README
      ### Required variables
      # MONGO_CONNECTION - The connection string for your Mongo database.
      # Something like mongodb://sally:sallypass@ds099999.mongolab.com:99999/nightscout
      # The default connects to the `mongo` included in this docker-compose file.
      # If you change it, you probably also want to comment out the entire `mongo` service block
      # and `depends_on` block above.
      MONGO_CONNECTION: mongodb://mongo:27017/nightscout

      # API_SECRET - A secret passphrase that must be at least 12 characters long.
      API_SECRET: ${NS-API-KEY}

      ### Features
      # ENABLE - Used to enable optional features, expects a space delimited list, such as: careportal rawbg iob
      # See https://github.com/nightscout/cgm-remote-monitor#plugins for details
      ENABLE: ${NS-FEATURES}

      # AUTH_DEFAULT_ROLES (readable) - possible values readable, denied, or any valid role name.
      # When readable, anyone can view Nightscout without a token. Setting it to denied will require
      # a token from every visit, using status-only will enable api-secret based login.
      AUTH_DEFAULT_ROLES: denied

      # For all other settings, please refer to the Environment section of the README
      # https://github.com/nightscout/cgm-remote-monitor#environment

networks:
  caddy:
    external: true

volumes:
  caddy_data: {}
EOD
docker network create caddy
docker-compose -f /nightscout/docker-compose.yml up -d
