#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  htop \
  jq \
  acl \
  unattended-upgrades \
  ufw

install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" \
  -o /etc/apt/keyrings/docker.asc
gpg --dearmor --yes \
  --output /etc/apt/keyrings/docker.gpg \
  /etc/apt/keyrings/docker.asc
chmod 0644 /etc/apt/keyrings/docker.gpg

. /etc/os-release
cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable
EOF

apt-get update
apt-get install -y --no-install-recommends \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

timedatectl set-timezone UTC
systemctl enable docker
systemctl enable systemd-timesyncd || true

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
