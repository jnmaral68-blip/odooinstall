#!/bin/bash

# Configuración
LISTA_REPOS="/opt/odoo/odooinstall/reposoca.txt"
DIR_BASE="/opt/odoo/oca"
BRANCH="18.0"

# 1. Preparar el sistema
echo "--- Preparando directorios y usuario ---"
sudo adduser --system --quiet --shell=/bin/bash --home=/opt/odoo --gecos 'odoo' --group odoo
sudo usermod -g odoo jnmar
cd /home/jnmar
./.bashrc
sudo mkdir -p /etc/odoo /var/log/odoo "$DIR_BASE"
sudo apt update && sudo apt install -y git postgresql

# 2. Clonar Odoo Base (OCB)
if [ ! -d "/opt/odoo/odoo" ]; then
    echo "--- Clonando OCB ---"
    git clone --depth 1 --branch $BRANCH https://github.com/SOLDIGES/OCB.git /opt/odoo/odoo
fi

# 3. Clonar repositorios desde la lista
if [ -f "$LISTA_REPOS" ]; then
    while IFS= read -r repo || [ -n "$repo" ]; do
        # Ignorar líneas vacías o comentarios
        [[ -z "$repo" || "$repo" =~ ^# ]] && continue
        
        echo "--- Clonando OCA: $repo ---"
        git clone --depth 1 --branch $BRANCH https://github.com/SOLDIGES/${repo}.git "$DIR_BASE/${repo}"
    done < "$LISTA_REPOS"
else
    echo "Error: No se encontró el archivo $LISTA_REPOS"
    exit 1
fi

# 4. Ajustar permisos (Crucial para que Odoo funcione)
echo "--- Ajustando permisos ---"
sudo chown -R odoo:odoo /opt/odoo
sudo chown -R odoo:odoo /var/log/odoo
sudo chmod -R 775 /opt/odoo/odoo

echo "¡Proceso finalizado!"
Usa el código con precaución.
