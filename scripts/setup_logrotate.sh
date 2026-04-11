#!/bin/bash

# Definimos el archivo de configuración en la carpeta estándar de Linux
LOGROTATE_CONF="/etc/logrotate.d/odoo"

echo "--- Configurando Logrotate para Odoo Maralva ---"

sudo bash -c "cat > $LOGROTATE_CONF <<EOF
/var/log/odoo/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 odoo odoo
	su odoo odoo
    sharedscripts
    postrotate
        /usr/bin/systemctl reload nginx > /dev/null 2>&1 || true
    endscript
}
EOF"

# Forzamos permisos correctos para que el sistema lo acepte
sudo chown root:root $LOGROTATE_CONF
sudo chmod 644 $LOGROTATE_CONF

echo "✅ Logrotate configurado: Guardará 14 días de logs comprimidos."

