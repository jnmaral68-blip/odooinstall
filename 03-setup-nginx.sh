
#!/bin/bash
# Variables necesarias (deben ser pasadas o heredadas)
BRANCH_DOMAIN=$(echo $BRANCH | cut -d. -f1)
BRANCH_CLEAN=$(echo $BRANCH | tr -d '.')
NGINX_CONF="/etc/nginx/sites-available/odoo$BRANCH"

echo "--- Configurando Nginx para rama $BRANCH ---"

# Usamos "EOF" (sin comillas) para permitir expansión de variables
sudo bash -c "cat > $NGINX_CONF <<EOF
upstream odoo_backend_$BRANCH_CLEAN {
    server 127.0.0.1:$ODOO_PORT;
}
upstream odoo_chat_$BRANCH_CLEAN {
    server 127.0.0.1:$ODOO_CHAT_PORT;
}

server {
    listen 80;
    server_name *.v$BRANCH_DOMAIN.$DOMAIN;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    client_max_body_size 128M;

    # Logs específicos por instancia
    access_log /var/log/nginx/odoo$BRANCH_access.log;
    error_log /var/log/nginx/odoo$BRANCH_error.log;

    location /longpolling {
        proxy_pass http://odoo_chat_$BRANCH_CLEAN;
    }

    location / {
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_pass http://odoo_backend_$BRANCH_CLEAN;
    }
}
EOF"

sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx