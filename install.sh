#!/bin/bash
# Pterodactyl + Wings Installer (No Domain, IP Only)
# For Ubuntu 22.04 - By ChatGPT

set -e

# === VARIABLES ===
PANEL_DIR=/var/www/pterodactyl
PANEL_DB=pteropanel
PANEL_DB_USER=pterouser
PANEL_DB_PASS="SuperStrongPassword123!"
PANEL_ADMIN_EMAIL="admin@example.com"

# === UPDATE SYSTEM ===
echo "[+] Updating system..."
apt update && apt upgrade -y

# === INSTALL DEPENDENCIES ===
echo "[+] Installing dependencies..."
apt install -y nginx mariadb-server redis-server php php-cli php-fpm \
php-mysql php-zip php-curl php-mbstring php-xml php-bcmath php-gd unzip curl git supervisor

# === CONFIGURE MYSQL ===
echo "[+] Setting up MariaDB..."
mysql -e "CREATE DATABASE ${PANEL_DB};"
mysql -e "CREATE USER '${PANEL_DB_USER}'@'127.0.0.1' IDENTIFIED BY '${PANEL_DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON ${PANEL_DB}.* TO '${PANEL_DB_USER}'@'127.0.0.1';"
mysql -e "FLUSH PRIVILEGES;"

# === INSTALL PANEL ===
echo "[+] Installing Pterodactyl panel..."
mkdir -p $PANEL_DIR && cd $PANEL_DIR
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache
cp .env.example .env

apt install -y composer
composer install --no-dev --optimize-autoloader

php artisan key:generate

sed -i "s/DB_DATABASE=.*/DB_DATABASE=${PANEL_DB}/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=${PANEL_DB_USER}/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${PANEL_DB_PASS}/" .env

php artisan migrate --seed --force
php artisan p:user:make --email=$PANEL_ADMIN_EMAIL --admin=1

chown -R www-data:www-data $PANEL_DIR

# === CONFIGURE NGINX ===
echo "[+] Configuring Nginx..."
cat > /etc/nginx/sites-available/pterodactyl <<EOF
server {
    listen 80;
    server_name _;
    root /var/www/pterodactyl/public;

    index index.php;
    access_log /var/log/nginx/pterodactyl.access.log;
    error_log  /var/log/nginx/pterodactyl.error.log error;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_index index.php;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -s /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

# === SUPERVISOR WORKER ===
echo "[+] Configuring queue worker..."
cat > /etc/supervisor/conf.d/pterodactyl.conf <<EOF
[program:pterodactyl-worker]
process_name=%(program_name)s_%(process_num)02d
command=php $PANEL_DIR/artisan queue:work --sleep=3 --tries=3
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=/var/log/worker.log
EOF

supervisorctl reread
supervisorctl update
supervisorctl start pterodactyl-worker:*

# === DONE ===
echo "✅ Panel is ready! Visit: http://YOUR.VPS.IP"
echo "➡ Login with the admin email: $PANEL_ADMIN_EMAIL"
echo "➡ Finish setup from the web interface"

# === WINGS NEXT ===
echo "➡ To install Wings (for server hosting), run: bash <(curl -s https://pterodactyl-installer.se/daemon)"
