#!/bin/bash

# ==========================================
# WordPress Auto Deployment Script
# Author: Ihtisham Hussain
# ==========================================

set -e

LOG_FILE="deployment.log"

log() {
    echo "$(date) : $1" | tee -a $LOG_FILE
}

echo "===================================="
echo " WordPress Auto Deployment Script"
echo "===================================="

read -p "Enter domain name: " DOMAIN
read -p "Enter database name: " DB_NAME
read -p "Enter database user: " DB_USER
read -s -p "Enter database password: " DB_PASS
echo

log "Starting deployment for $DOMAIN"

# Update system
log "Updating packages..."
sudo apt update -y

# Install Apache
log "Installing Apache..."
sudo apt install apache2 -y

# Install MariaDB
log "Installing MariaDB..."
sudo apt install mariadb-server -y

# Install PHP
log "Installing PHP..."
sudo apt install php libapache2-mod-php php-mysql php-cli php-curl php-xml php-mbstring php-zip unzip wget -y

# Enable Apache
sudo systemctl enable apache2
sudo systemctl start apache2

# Create database
log "Creating database..."

sudo mysql -e "CREATE DATABASE $DB_NAME;"
sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Download WordPress
log "Downloading WordPress..."

cd /tmp
wget https://wordpress.org/latest.zip
unzip latest.zip

# Move WordPress
sudo mkdir -p /var/www/$DOMAIN
sudo cp -r wordpress/* /var/www/$DOMAIN/

# Configure WordPress
log "Configuring WordPress..."

cd /var/www/$DOMAIN

sudo cp wp-config-sample.php wp-config.php

sudo sed -i "s/database_name_here/$DB_NAME/" wp-config.php
sudo sed -i "s/username_here/$DB_USER/" wp-config.php
sudo sed -i "s/password_here/$DB_PASS/" wp-config.php

# Permissions
log "Setting permissions..."

sudo chown -R www-data:www-data /var/www/$DOMAIN
sudo chmod -R 755 /var/www/$DOMAIN

# Apache virtual host
log "Creating virtual host..."

sudo bash -c "cat > /etc/apache2/sites-available/$DOMAIN.conf" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot /var/www/$DOMAIN

    <Directory /var/www/$DOMAIN>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>
EOF

# Enable site
sudo a2ensite $DOMAIN.conf
sudo a2enmod rewrite

# Validate Apache configuration
log "Checking Apache configuration..."
sudo apache2ctl configtest

# Restart Apache
sudo systemctl restart apache2

log "Deployment completed successfully!"

echo "===================================="
echo " WordPress deployed successfully!"
echo "===================================="
