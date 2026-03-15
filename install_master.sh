#!/bin/bash

# --- 1. SOLICITUD DE DATOS (Interactivo) ---
echo "=============================================="
echo " CONFIGURACIÓN DE INSTANCIA ODOO "
echo "=============================================="

read -p "Rama de Odoo/OCA (ej. 18.0, 19.0): " BRANCH
if [ -z "$BRANCH" ]; then echo "Error: Rama obligatoria"; exit 1; fi
export BRANCH

read -p "Organización de GitHub (tu fork): " ORGANIZACION
if [ -z "$ORGANIZACION" ]; then echo "Error: Organización obligatoria"; exit 1; fi
export ORGANIZACION

read -p "Dominio base: " DOMAIN
if [ -z "$DOMAIN" ]; then echo "Error: Dominio obligatorio"; exit 1; fi
export DOMAIN

read -p "Puerto HTTP: " ODOO_PORT
if [ -z "$ODOO_PORT" ]; then echo "Error: Puerto HTTP obligatorio"; exit 1; fi
export ODOO_PORT

read -p "Puerto Longpolling: " ODOO_CHAT_PORT
if [ -z "$ODOO_CHAT_PORT" ]; then echo "Error: Puerto Longpolling obligatorio"; exit 1; fi
export ODOO_CHAT_PORT

# --- 2. CÁLCULO DE VARIABLES DERIVADAS (Exportadas) ---
export BRANCH_CLEAN
BRANCH_CLEAN=$(echo "$BRANCH" | tr -d '.')
export BRANCH_DOMAIN
BRANCH_DOMAIN=$(echo "$BRANCH" | cut -d. -f1)
# Usamos BRANCH_CLEAN para evitar puntos en el nombre del servicio (odoo180, odoo190, etc.)
export SERVICE_NAME="odoo${BRANCH_CLEAN}"
# Estructura de directorios por versión mayor: /opt/odoo/18, /opt/odoo/19, etc.
export BASE_INSTANCIA="/opt/odoo/$BRANCH_DOMAIN"
export DIR_CORE="$BASE_INSTANCIA/odoo"
export DIR_OCA="$BASE_INSTANCIA/oca"
export DIR_VENV="$BASE_INSTANCIA/venv"
export CONF_FILE="/etc/odoo/$SERVICE_NAME.conf"
export LOG_DIR="/var/log/odoo"

# Ruta al archivo de repositorios (asumiendo que está en la carpeta del script)
export LISTA_REPOS="$(pwd)/reposoca.txt"

# --- 3. LANZAMIENTO DE MÓDULOS ---
chmod +x $(pwd)/01-prep-db.sh $(pwd)/02-odoo-setup.sh $(pwd)/03-setup-nginx.sh

echo -e "\n>>> Iniciando Fase 1: Sistema y PostgreSQL..."
$(pwd)/01-prep-db.sh || { echo "Falló Fase 1"; exit 1; }

echo -e "\n>>> Iniciando Fase 2: Odoo Core, OCA y Venv..."
$(pwd)/02-odoo-setup.sh || { echo "Falló Fase 2"; exit 1; }

echo -e "\n>>> Iniciando Fase 3: Nginx..."
$(pwd)/03-setup-nginx.sh || { echo "Falló Fase 3"; exit 1; }

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