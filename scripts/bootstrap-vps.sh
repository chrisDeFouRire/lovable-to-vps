#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
data_root=${1:-/mnt/data}
[ -d "$data_root" ] || { echo "data root does not exist: $data_root" >&2; exit 1; }

echo "Installing Ubuntu-packaged Docker, Compose, and Caddy"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2 caddy curl jq openssl python3

systemctl stop docker.service docker.socket 2>/dev/null || true
install -d -m 711 "$data_root/docker" /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "$data_root/docker",
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
chmod 644 /etc/docker/daemon.json
systemctl enable --now docker
systemctl enable --now caddy

docker info --format 'Docker={{.ServerVersion}} DataRoot={{.DockerRootDir}}'
docker compose version
docker run --rm hello-world >/dev/null
systemctl is-active docker caddy
printf 'Docker smoke test passed; data root: %s/docker\n' "$data_root"
echo 'The operator was not added to the root-equivalent docker group; use sudo docker.'
