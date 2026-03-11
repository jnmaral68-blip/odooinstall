#!/bin/bash

# Configuración
LISTA_REPOS="/opt/odoo/odooinstall/reposoca.txt"
DIR_BASE="/opt/odoo/oca"
BRANCH="18.0"

# 1. Preparar el sistema
echo "--- Preparando directorios y usuario ---"
sudo adduser --system --quiet --shell=/bin/bash --home=/opt/odoo --gecos 'odoo' --group odoo
sudo mkdir -p /etc/odoo /var/log/odoo "$DIR_BASE"
sudo apt update && sudo apt install -y git postgresql

# SOLUCIÓN AL ERROR DE PROPIEDAD: Marcar /opt/odoo como seguro para Git
sudo git config --global --add safe.directory '*'

# Asegurar permisos iniciales para que el usuario 'odoo' pueda escribir
sudo chown -R odoo:odoo /opt/odoo

# 2. Clonar Odoo Base (OCB) y configurar Upstream
if [ ! -d "/opt/odoo/odoo" ]; then
    echo "--- Clonando OCB ---"
    sudo -u odoo git clone --depth 1 --branch $BRANCH https://github.com/SOLDIGES/OCB.git /opt/odoo/odoo
    
    # Usamos -C para no tener que hacer 'cd' y evitar problemas de rutas
    if ! sudo -u odoo git -C /opt/odoo/odoo remote | grep -q "upstream"; then
        echo "--- Configurando upstream para OCB ---"
        sudo -u odoo git -C /opt/odoo/odoo remote add upstream "https://github.com/OCA/OCB.git"
    fi
fi

# 3. Clonar repositorios desde la lista y configurar Upstream
if [ -f "$LISTA_REPOS" ]; then
    while IFS= read -r repo || [ -n "$repo" ]; do
        [[ -z "$repo" || "$repo" =~ ^# ]] && continue
        
        TARGET_DIR="$DIR_BASE/${repo}"
        # CORRECCIÓN: Se añade $ a ${repo}
        MY_FORK="https://github.com/SOLDIGES/${repo}.git"
        OCA_REPO="https://github.com/OCA/${repo}.git"

        if [ ! -d "$TARGET_DIR" ]; then
            echo "--- Intentando clonar tu fork: $repo ---"
            if sudo -u odoo git clone --depth 1 --branch $BRANCH "$MY_FORK" "$TARGET_DIR" 2>/dev/null; then
                echo "Fork clonado correctamente."
            else
                echo "Aviso: Fork no encontrado. Clonando original de la OCA..."
                sudo -u odoo git clone --depth 1 --branch $BRANCH "$OCA_REPO" "$TARGET_DIR"
            fi
        fi

        # Configuración de remotos usando -C (más robusto en scripts)
        if ! sudo -u odoo git -C "$TARGET_DIR" remote | grep -q "upstream"; then
            sudo -u odoo git -C "$TARGET_DIR" remote add upstream "$OCA_REPO"
        else
            sudo -u odoo git -C "$TARGET_DIR" remote set-url upstream "$OCA_REPO"
        fi

        # Preparar origin para tu fork futuro
        sudo -u odoo git -C "$TARGET_DIR" remote set-url origin "$MY_FORK"

    done < "$LISTA_REPOS"
else
    echo "Error: No se encontró el archivo $LISTA_REPOS"
    exit 1
fi

# 4. Ajustar permisos finales
echo "--- Ajustando permisos finales ---"
sudo chown -R odoo:odoo /opt/odoo
sudo chown -R odoo:odoo /var/log/odoo
sudo chmod -R 775 /opt/odoo/

echo "¡Proceso finalizado!"