#!/usr/bin/env bash
# Один раз готовит чистый Ubuntu 24.04: Docker, файрвол, автообновления безопасности.
# Запускается с Mac: make server-setup HOST=root@1.2.3.4
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -q
apt-get install -y -q docker.io docker-compose-v2 rsync ufw unattended-upgrades
systemctl enable --now docker

# Наружу — только SSH и HTTPS (80 нужен Caddy для получения сертификата).
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

mkdir -p /opt/levelup/backups
docker compose version
echo "Сервер готов."
