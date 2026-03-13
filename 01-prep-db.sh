#!/bin/bash
set -e
# Reutilizamos tu lógica de usuario y dependencias
REAL_USER=${SUDO_USER:-$USER}
sudo id -u odoo &>/dev/null || sudo adduser --system --quiet --shell=/bin/bash --home /opt/odoo --group odoo

echo "--- Instalando dependencias del sistema ---"
sudo apt update && sudo apt install -y git postgresql python3-venv python3-dev build-essential libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev libssl-dev libpq-dev libjpeg-dev nginx

echo "--- Configurando PostgreSQL ---"
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='odoo'" | grep -q 1; then
    sudo -u postgres createuser -s odoo
fi