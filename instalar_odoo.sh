#!/bin/bash

# 1. Configuración dinámica del usuario que ejecuta ---
	REAL_USER=${SUDO_USER:-$USER}
	USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
	LISTA_REPOS="$USER_HOME/odooinstall/reposoca.txt"

# 2. Solicitud de la Rama y Organización ---
	echo "Indique la rama de Odoo/OCA (ej. 17.0, 18.0):"
	read -p "[Por defecto 18.0]: " BRANCH
	BRANCH=${BRANCH:-18.0}

# 	--- NUEVA SOLICITUD DE ORGANIZACIÓN ---
	echo "Indique la Organización de GitHub (ej. acme-odoo):"
	read -p "ORGANIZACION: " ORGANIZACION
	if [ -z "$ORGANIZACION" ]; then
		echo "Error: La organización es obligatoria."
		exit 1
	fi

# 3. Definición de la nueva estructura: /opt/odoo/odoo18.0/
	BASE_INSTANCIA="/opt/odoo/odoo$BRANCH"
	DIR_CORE="$BASE_INSTANCIA/odoo"
	DIR_OCA="$BASE_INSTANCIA/oca"

	echo "--- Iniciando instalación en $BASE_INSTANCIA ---"

# 4. Preparar el sistema
	echo "--- Preparando directorios y usuario odoo ---"
	sudo adduser --system --quiet --shell=/bin/bash --home=/opt/odoo --gecos 'odoo' --group odoo
	sudo mkdir -p /etc/odoo /var/log/odoo "$DIR_CORE" "$DIR_OCA"
	sudo apt update && sudo apt install -y git postgresql

# 5. Configurar PostgreSQL
	echo "--- Configurando Base de Datos ---"
	if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='odoo'" | grep -q 1; then
		sudo -u postgres createuser -s odoo
	fi

# 6. Crear la base de datos para esta rama si no existe
	DB_NAME="odoo$BRANCH"
	if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
		echo "Creando base de datos $DB_NAME..."
		sudo -u postgres createdb -O odoo "$DB_NAME"
	else
		echo "La base de datos $DB_NAME ya existe."
	fi

# 7. Instalación de wkhtmltopdf ---
	if ! command -v wkhtmltopdf &> /dev/null; then
		echo "--- Instalando wkhtmltopdf ---"
		sudo apt install -y xfonts-75dpi xfonts-base fontconfig libxrender1
		WK_URL="https://github.com"
		wget "$WK_URL" -O /tmp/wkhtmltopdf.deb
		sudo apt install -y /tmp/wkhtmltopdf.deb
		rm /tmp/wkhtmltopdf.deb
		sudo ln -s /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf
	else
		echo "--- wkhtmltopdf ya está instalado ---"
	fi

# 8. SOLUCIÓN DEFINITIVA 'dubious ownership'
	sudo git config --system --add safe.directory '*'
	sudo chown -R odoo:odoo /opt/odoo

# 9. Clonar OCB (Core) --- ACTUALIZADO CON ORGANIZACIÓN ---
	if [ ! -d "$DIR_CORE/.git" ]; then
		echo "--- Clonando OCB $BRANCH desde $ORGANIZACION ---"
		sudo -u odoo git clone --depth 1 --branch "$BRANCH" "https://github.com/$ORGANIZACIÓN/OCB.git" "$DIR_CORE"
	fi

	if [ -d "$DIR_CORE" ]; then
		if ! sudo -u odoo git -C "$DIR_CORE" remote | grep -q "upstream"; then
			sudo -u odoo git -C "$DIR_CORE" remote add upstream "https://github.com/OCA/OCB.git"
		fi
	fi

# 10. Clonar repositorios de la lista --- ACTUALIZADO CON ORGANIZACIÓN ---
	if [ -f "$LISTA_REPOS" ]; then
		while IFS= read -r repo || [ -n "$repo" ]; do
			[[ -z "$repo" || "$repo" =~ ^# ]] && continue
        
			TARGET_DIR="$DIR_OCA/${repo}"
			MY_FORK="https://github.com/$ORGANIZACIÓN/${repo}.git"
			OCA_REPO="https://github.com/OCA/${repo}.git"

        if [ ! -d "$TARGET_DIR" ]; then
            echo "--- Repositorio: $repo ---"
            if sudo -u odoo git clone --depth 1 --branch "$BRANCH" "$MY_FORK" "$TARGET_DIR" 2>/dev/null; then
                echo "   [OK] Fork de $ORGANIZACION clonado."
            else
                echo "   [!] Fork no encontrado en $ORGANIZACION. Clonando de OCA..."
                sudo -u odoo git clone --depth 1 --branch "$BRANCH" "$OCA_REPO" "$TARGET_DIR"
            fi
        fi

        if [ -d "$TARGET_DIR" ]; then
            if ! sudo -u odoo git -C "$TARGET_DIR" remote | grep -q "upstream"; then
                sudo -u odoo git -C "$TARGET_DIR" remote add upstream "$OCA_REPO"
            fi
            sudo -u odoo git -C "$TARGET_DIR" remote set-url origin "$MY_FORK"
        fi
    done < "$LISTA_REPOS"
else
    echo "Error: No existe el archivo $LISTA_REPOS"
    exit 1
fi

# 11. Ajustar permisos finales
sudo chown -R odoo:odoo /opt/odoo
sudo chown -R odoo:odoo /var/log/odoo
sudo chmod -R 775 /opt/odoo/

echo "--- Proceso finalizado en $BASE_INSTANCIA ---"

# 12. Configuración del VENV ---
DIR_VENV="$BASE_INSTANCIA/venv"

# 13. Instalar dependencias necesarias para Python y Odoo
echo "--- Instalando dependencias de sistema para Python ---"
sudo apt install -y python3-venv python3-dev build-essential libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev libssl-dev libpq-dev libjpeg-dev

# 14. Crear el entorno virtual si no existe
if [ ! -d "$DIR_VENV" ]; then
    echo "--- Creando entorno virtual en $DIR_VENV ---"
    sudo -u odoo python3 -m venv "$DIR_VENV"
    
    # Actualizar pip dentro del entorno
    sudo -u odoo "$DIR_VENV/bin/pip" install --upgrade pip
fi

# 15. Instalar requerimientos del Core de Odoo
if [ -f "$DIR_CORE/requirements.txt" ]; then
    echo "--- Instalando dependencias de Odoo Core ---"
    sudo -u odoo "$DIR_VENV/bin/pip" install -r "$DIR_CORE/requirements.txt"
fi

# 16. Generar lista de addons para el odoo.conf
echo "--- Generando addons_path para tu configuración ---"
ADDONS_PATH="$DIR_CORE/addons"
# Buscamos todas las subcarpetas dentro de /oca/ y las añadimos
for d in "$DIR_OCA"/*; do
    if [ -d "$d" ]; then
        ADDONS_PATH="$ADDONS_PATH,$d"
    fi
done

echo "-----------------------------------------------------------"
echo "Copia esta línea en tu archivo odoo.conf:"
echo "addons_path = $ADDONS_PATH"
echo "-----------------------------------------------------------"

# 17. Generar Servicio Systemd ---
SERVICE_NAME="odoo$BRANCH"
FILE_SERVICE="/etc/systemd/system/$SERVICE_NAME.service"
CONF_FILE="/etc/odoo/$SERVICE_NAME.conf"

echo "--- Generando archivo de servicio en $FILE_SERVICE ---"
sudo bash -c "cat > $FILE_SERVICE <<EOF
[Unit]
Description=Odoo $BRANCH Service
After=postgresql.service

[Service]
Type=simple
User=odoo
Group=odoo
ExecStart=$DIR_VENV/bin/python3 $DIR_CORE/odoo-bin -c $CONF_FILE
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF"

# 18. Recargar daemon y habilitar (pero no arrancar hasta tener el .conf listo)
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"