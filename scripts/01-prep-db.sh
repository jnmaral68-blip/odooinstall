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

# Establecemos la contraseña para que pgAdmin no proteste
sudo -u postgres psql -c "ALTER USER odoo WITH PASSWORD 'odoo';"

echo "--- Habilitando conexiones externas para PgAdmin ---"

# 1. Detectar versión de Postgres instalada
PG_VER=$(psql --version | grep -P -o '\d+(?=\.\d+)' | head -1)
PG_CONF="/etc/postgresql/$PG_VER/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VER/main/pg_hba.conf"

# 2. Permitir que escuche en todas las interfaces (listen_addresses)
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

# 3. Añadir permiso a tu rango de red local en pg_hba.conf
# Ajustamos para que acepte cualquier IP de tu red doméstica (192.168.1.x)
if ! sudogrep -q "0.0.0.0/0" "$PG_HBA"; then
    echo "host    all             all             0.0.0.0/0               trust" | sudo tee -a "$PG_HBA"
fi

# 4. Reiniciar para aplicar cambios
sudo systemctl restart postgresql