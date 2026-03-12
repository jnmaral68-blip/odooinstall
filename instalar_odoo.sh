#!/bin/bash

# 1. Configuración dinámica del usuario que ejecuta ---
	REAL_USER=${SUDO_USER:-$USER}
	USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
	LISTA_REPOS="$USER_HOME/odooinstall/reposoca.txt"

# 2. Solicitud de Rama, Organización y PUERTOS ---
	echo "Indique la rama de Odoo/OCA (ej. 18.0, 19.0):"
	read -p "[Por defecto 18.0]: " BRANCH
	BRANCH=${BRANCH:-18.0}

	echo "Indique la Organización de GitHub (ej. acme-odoo):"
	read -p "ORGANIZACION: " ORGANIZACION
	if [ -z "$ORGANIZACION" ]; then
		echo "Error: La organización es obligatoria."
		exit 1
	fi

	echo "Indique el Puerto HTTP (Sugerido: 8069 para v18, 9069 para v19):"
	read -p "PUERTO HTTP: " ODOO_PORT
	ODOO_PORT=${ODOO_PORT:-8069}

	echo "Indique el Puerto Longpolling (Sugerido: 8072 para v18, 9072 para v19):"
	read -p "PUERTO CHAT: " ODOO_CHAT_PORT
	ODOO_CHAT_PORT=${ODOO_CHAT_PORT:-8072}

# 3. Definición de la nueva estructura
	BASE_INSTANCIA="/opt/odoo/odoo$BRANCH"
	DIR_CORE="$BASE_INSTANCIA/odoo"
	DIR_OCA="$BASE_INSTANCIA/oca"
	DIR_VENV="$BASE_INSTANCIA/venv"
	SERVICE_NAME="odoo$BRANCH"
	CONF_FILE="/etc/odoo/$SERVICE_NAME.conf"
	LOG_DIR="/var/log/odoo"

	echo "--- Iniciando instalación en $BASE_INSTANCIA (Puerto: $ODOO_PORT) ---"

# 4. Preparar el sistema
	echo "--- Preparando directorios y usuario odoo ---"
	# Usamos --system pero permitimos que el home sea /opt/odoo
	sudo id -u odoo &>/dev/null || sudo adduser --system --quiet --shell=/bin/bash --home /opt/odoo --group odoo
	sudo mkdir -p /etc/odoo "$LOG_DIR" "$DIR_CORE" "$DIR_OCA"
	sudo apt update && sudo apt install -y git postgresql python3-venv python3-dev build-essential libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev libssl-dev libpq-dev libjpeg-dev

# 5. Configurar PostgreSQL
	echo "--- Configurando Base de Datos ---"
	if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='odoo'" | grep -q 1; then
		sudo -u postgres createuser -s odoo
	fi

# 6. Crear la base de datos para esta rama si no existe
	DB_NAME="odoo$(echo $BRANCH | tr -d '.')" # Limpia el punto: odoo180
	if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
		echo "Creando base de datos $DB_NAME..."
		sudo -u postgres createdb -O odoo "$DB_NAME"
	fi

# 7. Clonar OCB y Repositorios
	sudo git config --system --add safe.directory '*'
	sudo chown -R odoo:odoo /opt/odoo
 
# 8. Clonar OCB (Core) --- ACTUALIZADO CON ORGANIZACIÓN ---
	if [ ! -d "$DIR_CORE/.git" ]; then
		echo "--- Clonando OCB $BRANCH desde $ORGANIZACION ---"
		sudo -u odoo git clone --depth 1 --branch "$BRANCH" "https://github.com/$ORGANIZACION/OCB.git" "$DIR_CORE"
	fi

	if [ -d "$DIR_CORE" ]; then
		if ! sudo -u odoo git -C "$DIR_CORE" remote | grep -q "upstream"; then
			sudo -u odoo git -C "$DIR_CORE" remote add upstream "https://github.com/OCA/OCB.git"
		fi
	fi

# 9. Clonar repositorios de la lista --- ACTUALIZADO CON ORGANIZACIÓN ---
	if [ -f "$LISTA_REPOS" ]; then
		while IFS= read -r repo || [ -n "$repo" ]; do
			[[ -z "$repo" || "$repo" =~ ^# ]] && continue
        
			TARGET_DIR="$DIR_OCA/${repo}"
			MY_FORK="https://github.com/$ORGANIZACION/${repo}.git"
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

# 10. Ajustar permisos finales
sudo chown -R odoo:odoo /opt/odoo
sudo chown -R odoo:odoo /var/log/odoo
sudo chmod -R 775 /opt/odoo/

echo "--- Proceso finalizado en $BASE_INSTANCIA ---"

# 11. Configuración del VENV ---
DIR_VENV="$BASE_INSTANCIA/venv"

# 12. Instalar dependencias necesarias para Python y Odoo
echo "--- Instalando dependencias de sistema para Python ---"
sudo apt install -y python3-venv python3-dev build-essential libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev libssl-dev libpq-dev libjpeg-dev

# 13. Crear el entorno virtual e instalar dependencias
	if [ ! -d "$DIR_VENV" ]; then
		echo "--- Creando entorno virtual en $DIR_VENV ---"
		sudo -u odoo python3 -m venv "$DIR_VENV"
		sudo -u odoo "$DIR_VENV/bin/pip" install --upgrade pip
	fi

	if [ -f "$DIR_CORE/requirements.txt" ]; then
		echo "--- Instalando dependencias de Odoo Core ---"
		sudo -u odoo "$DIR_VENV/bin/pip" install -r "$DIR_CORE/requirements.txt"
	fi

# 14. GENERACIÓN AUTOMÁTICA DEL ODOO.CONF
	echo "--- Generando archivo de configuración en $CONF_FILE ---"
	ADDONS_PATH="$DIR_CORE/addons"
	for d in "$DIR_OCA"/*; do
		[ -d "$d" ] && ADDONS_PATH="$ADDONS_PATH,$d"
	done

	sudo bash -c "cat > $CONF_FILE <<EOF
[options]
admin_passwd = admin_password
db_user = odoo
db_name = $DB_NAME
http_port = $ODOO_PORT
longpolling_port = $ODOO_CHAT_PORT
addons_path = $ADDONS_PATH
logfile = $LOG_DIR/$SERVICE_NAME.log
EOF"
	sudo chown odoo: /etc/odoo/*.conf
	sudo chmod 640 /etc/odoo/*.conf

# 15. Generar Servicio Systemd
	echo "--- Generando archivo de servicio en /etc/systemd/system/$SERVICE_NAME.service ---"
	sudo bash -c "cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
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

# 17. Finalización
	sudo systemctl daemon-reload
	sudo systemctl enable "$SERVICE_NAME"
	sudo chown -R odoo:odoo /opt/odoo /var/log/odoo

	echo "--- INSTALACIÓN COMPLETADA ---"
	echo "Instancia: $SERVICE_NAME"
	echo "Acceso: http://tu-ip:$ODOO_PORT"
	echo "Config: $CONF_FILE"