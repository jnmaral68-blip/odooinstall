#!/bin/bash

# 1. Configuración dinámica del usuario que ejecuta ---
	REAL_USER=${SUDO_USER:-$USER}
	USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
	# LISTA_REPOS se obtiene de las variables exportadas en install_master.sh

# 2. Variables obtenidas de install_master.sh (BRANCH, ORGANIZACION, ODOO_PORT, ODOO_CHAT_PORT, DOMAIN, LISTA_REPOS)

# 3. Definición de la nueva estructura
	BASE_INSTANCIA="/opt/odoo/odoo$BRANCH"
	DIR_CORE="$BASE_INSTANCIA/odoo"
	DIR_OCA="$BASE_INSTANCIA/oca"
	DIR_VENV="$BASE_INSTANCIA/venv"
	SERVICE_NAME="odoo$BRANCH"
	CONF_FILE="/etc/odoo/$SERVICE_NAME.conf"
	LOG_DIR="/var/log/odoo"

echo "--- Clonando y configurando Odoo $BRANCH ---"
sudo mkdir -p /etc/odoo "$LOG_DIR" "$DIR_CORE" "$DIR_OCA"
sudo chown -R odoo:odoo /opt/odoo /var/log/odoo
sudo git config --system --add safe.directory '*'

# 8. Clonar OCB (Core) --- ACTUALIZADO CON ORGANIZACIÓN ---
	if [ ! -d "$DIR_CORE/.git" ]; then
		echo "--- Clonando OCB $BRANCH desde $ORGANIZACION ---"
		odoo git clone --depth 1 --branch "$BRANCH" "git@github.com:$ORGANIZACION/OCB.git" "$DIR_CORE"
	fi
	sudo chown -R odoo:odoo "$DIR_CORE"
	if [ -d "$DIR_CORE" ]; then
		cd "$DIR_CORE"
		if ! git remote | grep -q "upstream"; then
			echo "---Añadiendo upstream OCA/OCB ---"
			odoo git remote add upstream "git@github.com:OCA/OCB.git"
			# Opcional: Traer metadatos del upstream sin bajar todo el historial
			odoo git fetch --depth 1 upstream "$BRANCH"
		fi
		# IMPORTANTE: Ahora le damos el control al usuario odoo
    	sudo chown -R odoo:odoo "$DIR_CORE"
	fi

# 9. Clonar repositorios de la lista
	if [ -f "$LISTA_REPOS" ]; then
		while IFS= read -r repo || [ -n "$repo" ]; do
			[[ -z "$repo" || "$repo" =~ ^# ]] && continue
        
			TARGET_DIR="$DIR_OCA/${repo}"
			MY_FORK="git@github.com:$ORGANIZACION/${repo}.git"
			OCA_REPO="git@github.com:OCA/${repo}.git"

        if [ ! -d "$TARGET_DIR" ]; then
            echo "--- Repositorio: $repo ---"
			# Intentar clonar Fork, si falla, clonar OCA
            if ! git clone --depth 1 --branch "$BRANCH" "$MY_FORK" "$TARGET_DIR" 2>/dev/null; then
                echo "   [OK] Fork de $ORGANIZACION clonado."
            else
                echo "   [!] Fork no encontrado en $ORGANIZACION. Clonando de OCA..."
                git clone --depth 1 --branch "$BRANCH" "$OCA_REPO" "$TARGET_DIR"
            fi
        fi
		sudo chown -R odoo:odoo "$DIR_OCA"
		# Configuración de remotes
        if [ -d "$TARGET_DIR" ]; then
			cd "$TARGET_DIR"
			# 1. Asegurar que origin es la Organización
			git remote set-url origin "$MY_FORK"
			# 2.- Añadir upstream (OCA) si no existe
            if ! git remote | grep -q "upstream"; then
                git remote add upstream "$OCA_REPO"
				git fetch --depth 1 upstream "$BRANCH"
            fi
			sudo chown -R odoo:odoo "$DIR_OCA"
        fi
    done < "$LISTA_REPOS"
else
    echo "Error: No existe el archivo $LISTA_REPOS"
    exit 1
fi

# Entorno Virtual y Dependencias (Puntos 11-13)
sudo -u odoo python3 -m venv "$DIR_VENV"
sudo -u odoo "$DIR_VENV/bin/pip" install --upgrade pip
[ -f "$DIR_CORE/requirements.txt" ] && sudo -u odoo "$DIR_VENV/bin/pip" install -r "$DIR_CORE/requirements.txt"

# 14. GENERACIÓN AUTOMÁTICA DEL ODOO.CONF
	echo "--- Generando archivo de configuración en $CONF_FILE ---"
	ADDONS_PATH="$DIR_CORE/addons"
	for d in "$DIR_OCA"/*; do
		[ -d "$d" ] && ADDONS_PATH="$ADDONS_PATH,$d"
	done

	sudo bash -c "cat > $CONF_FILE <<EOF
[options]
db_user = odoo
http_port = $ODOO_PORT
proxy_mode = True
dbfilter = ^%d$
longpolling_port = $ODOO_CHAT_PORT
addons_path = $ADDONS_PATH
logfile = $LOG_DIR/$SERVICE_NAME.log
xmlrpc_interface = 0.0.0.0
netrpc_interface = 0.0.0.0
workers = 5
EOF"
	sudo chown odoo: /etc/odoo/*.conf
	sudo chmod 640 /etc/odoo/*.conf

# 15. Generar Servicio Systemd ---
SERVICE_NAME="odoo$BRANCH"
FILE_SERVICE="/etc/systemd/system/$SERVICE_NAME.service"
CONF_FILE="/etc/odoo/$SERVICE_NAME.conf"

echo "--- Generando archivo de servicio en $FILE_SERVICE ---"
sudo bash -c "cat > $FILE_SERVICE <<EOF
[Unit]
Description=Odoo $BRANCH Service
After=network.target postgresql.service

[Service]
Type=simple
User=odoo
Group=odoo
# Usamos la ruta absoluta del python del venv y del odoo-bin
ExecStart=$DIR_VENV/bin/python3 $DIR_CORE/odoo-bin -c $CONF_FILE
# Esto asegura que si falla, intente reiniciar solo
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF"