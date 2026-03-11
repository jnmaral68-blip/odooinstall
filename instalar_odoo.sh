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

# 2. Clonar Odoo Base (OCB) y configurar Upstream
if [ ! -d "/opt/odoo/odoo" ]; then
    echo "--- Clonando OCB ---"
    git clone --depth 1 --branch $BRANCH https://github.com/SOLDIGES/OCB.git /opt/odoo/odoo
	
	# Entrar al directorio para configurar el Upstream
        cd /opt/odoo/odoo || continue

        # Añadir el remoto original de la OCA si no existe
        if ! git remote | grep -q "upstream"; then
            echo "--- Configurando upstream para $repo ---"
            git remote add upstream "https://github.com/OCA/OCB.git"
        fi
fi

# 3. Clonar repositorios desde la lista y configurar Upstream
if [ -f "$LISTA_REPOS" ]; then
    while IFS= read -r repo || [ -n "$repo" ]; do
        [[ -z "$repo" || "$repo" =~ ^# ]] && continue
        
        TARGET_DIR="$DIR_BASE/${repo}"
        MY_FORK="https://github.com/SOLDIGES/{repo}.git"
        OCA_REPO="https://github.com/OCA/{repo}.git"

        if [ ! -d "$TARGET_DIR" ]; then
            echo "--- Intentando clonar tu fork: $repo ---"
            # Intentar clonar tu fork; si falla (2>/dev/null), clona el de la OCA
            if git clone --depth 1 --branch $BRANCH "$MY_FORK" "$TARGET_DIR" 2>/dev/null; then
                echo "Fork clonado correctamente."
            else
                echo "Aviso: Fork no encontrado. Clonando original de la OCA..."
                git clone --depth 1 --branch $BRANCH "$OCA_REPO" "$TARGET_DIR"
            fi
        fi

        # Entrar al directorio para asegurar la configuración de remotos
        cd "$TARGET_DIR" || continue

        # 1. Asegurar que 'upstream' apunte SIEMPRE al original de la OCA
        if ! git remote | grep -q "upstream"; then
            git remote add upstream "$OCA_REPO"
        else
            git remote set-url upstream "$OCA_REPO"
        fi

        # 2. Si clonaste el de la OCA por error como 'origin', cámbialo a tu fork
        # Esto prepara el terreno para cuando hagas el fork en el futuro
        git remote set-url origin "$MY_FORK"

        cd - > /dev/null
    done < "$LISTA_REPOS"
else
    echo "Error: No se encontró el archivo $LISTA_REPOS"
    exit 1
fi

# 4. Ajustar permisos (Crucial para que Odoo funcione)
echo "--- Ajustando permisos ---"
sudo chown -R odoo:odoo /opt/odoo
sudo chown -R odoo:odoo /var/log/odoo
sudo chown -R jnmar:odoo /opt/odoo/odooinstall
sudo chmod -R 775 /opt/odoo/

echo "¡Proceso finalizado!"