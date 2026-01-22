#!/bin/bash
# deploy-to-pi.sh
# Deploy Falcon Gateway to Raspberry Pi running Fedora IoT
#
# Usage: ./deploy-to-pi.sh [user@host]
# Example: ./deploy-to-pi.sh falcon@192.168.1.233

set -euo pipefail

TARGET="${1:-falcon@192.168.1.233}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "  Falcon Gateway - Pi Deployment"
echo "=========================================="
echo "Target: $TARGET"
echo "Source: $REPO_DIR"
echo ""

# Check SSH connectivity
echo "[1/6] Checking connectivity..."
if ! ssh -o ConnectTimeout=5 "$TARGET" "echo 'Connected'" 2>/dev/null; then
    echo "ERROR: Cannot connect to $TARGET"
    exit 1
fi
echo "OK: Connected"

# Create directories on Pi
echo ""
echo "[2/6] Creating directories..."
ssh "$TARGET" "sudo mkdir -p /etc/falcon/{traefik/dynamic,prometheus,grafana/provisioning/datasources} /var/lib/falcon/{redis,consul,prometheus,grafana}"

# Copy Quadlet files
echo ""
echo "[3/6] Deploying Quadlet container definitions..."
scp "$REPO_DIR/quadlet/"*.{container,network} "$TARGET:/tmp/"
ssh "$TARGET" "sudo mv /tmp/*.container /tmp/*.network /etc/containers/systemd/"

# Copy configurations
echo ""
echo "[4/6] Deploying configurations..."
scp "$REPO_DIR/configs/traefik/traefik.yml" "$TARGET:/tmp/"
scp "$REPO_DIR/configs/traefik/dynamic/routes.yml" "$TARGET:/tmp/routes.yml"
scp "$REPO_DIR/configs/prometheus/prometheus.yml" "$TARGET:/tmp/"
scp "$REPO_DIR/configs/grafana/provisioning/datasources/datasources.yml" "$TARGET:/tmp/datasources.yml"

ssh "$TARGET" "
    sudo mv /tmp/traefik.yml /etc/falcon/traefik/
    sudo mv /tmp/routes.yml /etc/falcon/traefik/dynamic/
    sudo mv /tmp/prometheus.yml /etc/falcon/prometheus/
    sudo mv /tmp/datasources.yml /etc/falcon/grafana/provisioning/datasources/
    sudo touch /etc/falcon/certs/acme.json
    sudo chmod 600 /etc/falcon/certs/acme.json
"

# Copy website
echo ""
echo "[5/6] Deploying website..."
scp "$REPO_DIR/website/index.html" "$TARGET:/tmp/"
ssh "$TARGET" "sudo mkdir -p /var/lib/falcon/website && sudo mv /tmp/index.html /var/lib/falcon/website/"

# Reload and start services
echo ""
echo "[6/6] Starting services..."
ssh "$TARGET" "
    sudo systemctl daemon-reload
    sudo systemctl enable --now falcon-redis.service
    sudo systemctl enable --now falcon-consul.service
    sudo systemctl enable --now falcon-traefik.service
    sudo systemctl enable --now falcon-prometheus.service
    sudo systemctl enable --now falcon-grafana.service
"

# Wait and check status
echo ""
echo "Waiting for services to start..."
sleep 5

echo ""
echo "=========================================="
echo "  Deployment Complete!"
echo "=========================================="
ssh "$TARGET" "sudo podman ps --format 'table {{.Names}}\t{{.Status}}'"

echo ""
echo "Service URLs:"
echo "  Website:    http://${TARGET#*@}:8081"
echo "  Traefik:    http://${TARGET#*@}:8080"
echo "  Consul:     http://${TARGET#*@}:8500"
echo "  Prometheus: http://${TARGET#*@}:9090"
echo "  Grafana:    http://${TARGET#*@}:3000"
echo ""
