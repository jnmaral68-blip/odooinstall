#!/bin/bash

# --- 1. SOLICITUD DE DATOS (Interactivo) ---
echo "=============================================="
echo " CONFIGURACIÓN DE INSTANCIA ODOO "
echo "=============================================="

read -p "Rama de Odoo/OCA (ej. 18.0, 19.0) [18.0]: " BRANCH
export BRANCH=${BRANCH:-18.0}

read -p "Organización de GitHub (tu fork): " ORGANIZACION
if [ -z "$ORGANIZACION" ]; then echo "Error: Organización obligatoria"; exit 1; fi
export ORGANIZACION

read -p "Dominio base [gdigital.loc]: " DOMAIN
export DOMAIN=${DOMAIN:-gdigital.loc}

read -p "Puerto HTTP [8069]: " ODOO_PORT
export ODOO_PORT=${ODOO_PORT:-8069}

read -p "Puerto Longpolling [8072]: " ODOO_CHAT_PORT
export ODOO_CHAT_PORT=${ODOO_CHAT_PORT:-8072}

# --- 2. CÁLCULO DE VARIABLES DERIVADAS (Exportadas) ---
export BRANCH_CLEAN=$(echo $BRANCH | tr -d '.')
export BRANCH_DOMAIN=$(echo $BRANCH | cut -d. -f1)
export SERVICE_NAME="odoo$BRANCH"
export BASE_INSTANCIA="/opt/odoo/odoo$BRANCH"
export DIR_CORE="$BASE_INSTANCIA/odoo"
export DIR_OCA="$BASE_INSTANCIA/oca"
export DIR_VENV="$BASE_INSTANCIA/venv"
export CONF_FILE="/etc/odoo/$SERVICE_NAME.conf"
export LOG_DIR="/var/log/odoo"

# Ruta al archivo de repositorios (asumiendo que está en la carpeta del script)
export LISTA_REPOS="$(pwd)/reposoca.txt"

# --- 3. LANZAMIENTO DE MÓDULOS ---
chmod +x 01-prep-db.sh 02-odoo-setup.sh 03-setup-nginx.sh

echo -e "\n>>> Iniciando Fase 1: Sistema y PostgreSQL..."
./01-prep-db.sh || { echo "Falló Fase 1"; exit 1; }

echo -e "\n>>> Iniciando Fase 2: Odoo Core, OCA y Venv..."
./02-odoo-setup.sh || { echo "Falló Fase 2"; exit 1; }

echo -e "\n>>> Iniciando Fase 3: Nginx..."
./03-setup-nginx.sh || { echo "Falló Fase 3"; exit 1; }

echo -e "\n=============================================="
echo "INSTALACIÓN FINALIZADA CON ÉXITO"
echo "URL: http://v$BRANCH_DOMAIN.$DOMAIN"
echo "Servicio: $SERVICE_NAME"
echo "Config: $CONF_FILE"
echo "=============================================="

# --- SECCIÓN 19: COMPROBACIÓN FINAL ---
echo -e "\n--- Verificando estado de los servicios ---"

# 1. Comprobar PostgreSQL
if systemctl is-active --quiet postgresql; then
    echo "[OK] PostgreSQL está ejecutándose."
else
    echo "[ERROR] PostgreSQL no parece estar activo."
fi

# 2. Comprobar el servicio específico de esta instancia de Odoo
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[OK] Servicio $SERVICE_NAME está ejecutándose."
else
    echo "[ERROR] El servicio $SERVICE_NAME falló al arrancar. Revisa: sudo journalctl -u $SERVICE_NAME"
fi

# 3. Comprobar Nginx
if systemctl is-active --quiet nginx; then
    echo "[OK] Nginx está ejecutándose."
else
    echo "[ERROR] Nginx no está activo. Revisa: sudo nginx -t"
fi

# 4. Comprobar que los puertos estén escuchando (requiere net-tools o iproute2)
echo "--- Puertos en escucha para esta instancia ---"
sudo ss -tunlp | grep -E ":$ODOO_PORT|:$ODOO_CHAT_PORT"

echo -e "\nInstancia Odoo $BRANCH lista en: http://v$BRANCH_DOMAIN.$DOMAIN"
echo "Log de Odoo disponible en: $LOG_DIR/$SERVICE_NAME.log"