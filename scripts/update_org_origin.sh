#!/bin/bash

# Script para subir (push) repositorios a origin (tu organización en GitHub) mediante SSH
# Uso: ./update_org_origin.sh

# Verificación de seguridad: Instantánea de la VM
echo "POR SEGURIDAD: ¿Has realizado una instantánea de la máquina virtual? (sí/no)"
read -p "Respuesta: " snapshot
if [[ "$snapshot" != "sí" && "$snapshot" != "si" && "$snapshot" != "yes" && "$snapshot" != "y" ]]; then
    echo "Operación cancelada. Realiza una instantánea antes de continuar."
    exit 1
fi

read -p "Rama de Odoo/OCA (ej. 18.0, 19.0) [18.0]: " BRANCH
BRANCH=${BRANCH:-18.0}
BRANCH_DOMAIN=$(echo "$BRANCH" | cut -d. -f1)
BRANCH_CLEAN=$(echo "$BRANCH" | tr -d '.')
BASE_INSTANCIA="/opt/odoo/$BRANCH_DOMAIN"
DIR_CORE="$BASE_INSTANCIA/odoo"
DIR_OCA="$BASE_INSTANCIA/oca"
LISTA_REPOS="$(pwd)/reposoca.txt"
SERVICE_NAME="odoo${BRANCH_CLEAN}"

if [ ! -f "$LISTA_REPOS" ]; then
    echo "Error: No se encuentra $LISTA_REPOS"
    exit 1
fi

echo "--- Subiendo repositorios a origin (tu organización) para rama $BRANCH ---"

read -p "¿Continuar? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operación cancelada."
    exit 0
fi

# Función para verificar estado del servicio Odoo
check_odoo_service() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "   [OK] Servicio $SERVICE_NAME sigue activo."
        return 0
    else
        echo "   [ERROR] Servicio $SERVICE_NAME caído. Revisa: sudo journalctl -u $SERVICE_NAME"
        return 1
    fi
}

# Función para subir un repo a origin
update_repo() {
    local repo_path=$1
    local repo_name=$(basename "$repo_path")
    
    if [ -d "$repo_path/.git" ]; then
        echo "--- Subiendo $repo_name ---"
        cd "$repo_path"
        if git push origin "$BRANCH"; then
            echo "   [OK] $repo_name subido a origin."
            # Verificar servicio después de cada repo para detectar incoherencias tempranas
            if ! check_odoo_service; then
                echo "   [ALERTA] Posible incoherencia detectada tras actualizar $repo_name. Deteniendo actualizaciones."
                return 1
            fi
        else
            echo "   [ERROR] Falló el push de $repo_name. Revisa logs."
            return 1
        fi
    else
        echo "   [SKIP] $repo_name no es un repositorio Git."
    fi
    return 0
}

# Subir core (origin = tu fork de OCB en la organización)
if ! update_repo "$DIR_CORE"; then
    echo "Error al subir core. Abortando."
    exit 1
fi

# Subir repos OCA (tus forks en la organización) desde lista
while IFS= read -r repo || [ -n "$repo" ]; do
    [[ -z "$repo" || "$repo" =~ ^# ]] && continue
    
    TARGET_DIR="$DIR_OCA/${repo}"
    if ! update_repo "$TARGET_DIR"; then
        echo "Error al subir $repo. Abortando."
        exit 1
    fi
done < "$LISTA_REPOS"

echo "--- Push a origin completado ---"
echo "Verificación final del servicio:"
check_odoo_service
echo "Reinicia el servicio Odoo si es necesario: sudo systemctl restart $SERVICE_NAME"
echo "Monitorea logs: journalctl -u $SERVICE_NAME -f"