#!/bin/bash

# ==========================================
# WordPress Auto Deployment Script
# Author: Ihtisham Hussain
# GitHub: wordpress-auto-deploy
# ==========================================

set -e

# ---- Colors ----
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---- Logging ----
LOG_FILE="/var/log/wpdeploy.log"
sudo touch "$LOG_FILE" 2>/dev/null && sudo chmod 666 "$LOG_FILE" 2>/dev/null || LOG_FILE="deployment.log"

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') : $1" | sudo tee -a "$LOG_FILE" > /dev/null
    echo -e "${CYAN}[LOG]${NC} $1"
}

success() { echo -e "${GREEN}[OK]${NC}  $1"; }
error()   { echo -e "${RED}[ERR]${NC} $1"; exit 1; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ---- Header ----
echo -e "${GREEN}"
echo "============================================"
echo "   WordPress Auto Deployment Script"
echo "============================================"
echo -e "${NC}"

# ==========================================
# SECTION 1 — Input & Validation
# ==========================================

read -p "Enter domain name (e.g. example.com): " DOMAIN
[[ -z "$DOMAIN" ]] && error "Domain name cannot be empty."

read -p "Enter database name: " DB_NAME
[[ -z "$DB_NAME" ]] && error "Database name cannot be empty."

read -p "Enter database user: " DB_USER
[[ -z "$DB_USER" ]] && error "Database user cannot be empty."

read -s -p "Enter database password: " DB_PASS
echo
[[ ${#DB_PASS} -lt 8 ]] && error "Password must be at least 8 characters."

read -p "Enable SSL with Certbot? (y/n): " ENABLE_SSL
read -p "Run backup after deployment? (y/n): " DO_BACKUP
read -p "Configure UFW firewall? (y/n): " ENABLE_UFW

log "Starting deployment for $DOMAIN"

# ==========================================
# SECTION 2 — System Update & LAMP Install
# ==========================================

log "Updating packages..."
sudo apt update -y >> "$LOG_FILE" 2>&1
success "Packages updated."

log "Installing Apache..."
sudo apt install apache2 -y >> "$LOG_FILE" 2>&1
success "Apache installed."

log "Installing MySQL..."
sudo apt install mysql-server -y >> "$LOG_FILE" 2>&1
success "MySQL installed."

log "Installing PHP and extensions..."
sudo apt install php libapache2-mod-php php-mysql php-cli \
    php-curl php-xml php-mbstring php-zip unzip wget -y >> "$LOG_FILE" 2>&1
success "PHP installed."

# ---- Enable Services ----
sudo systemctl enable apache2 && sudo systemctl start apache2
sudo systemctl enable mysql   && sudo systemctl start mysql
success "Apache and MySQL services started."

# ==========================================
# SECTION 3 — Database Setup
# ==========================================

log "Creating MySQL database and user..."

# Check if database already exists
DB_EXISTS=$(sudo mysql -sse "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DB_NAME';")
if [[ "$DB_EXISTS" -gt 0 ]]; then
    warn "Database '$DB_NAME' already exists — skipping creation."
else
    sudo mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
    success "Database '$DB_NAME' and user '$DB_USER' created."
fi

# ==========================================
# SECTION 4 — WordPress Download & Install
# ==========================================

log "Downloading WordPress..."
cd /tmp
wget -q https://wordpress.org/latest.zip -O latest.zip
unzip -q -o latest.zip
success "WordPress downloaded."

log "Moving WordPress files to /var/www/$DOMAIN..."
sudo mkdir -p /var/www/"$DOMAIN"
sudo cp -r wordpress/* /var/www/"$DOMAIN"/

# ==========================================
# SECTION 5 — WordPress Configuration
# ==========================================

log "Configuring wp-config.php..."
cd /var/www/"$DOMAIN"
sudo cp wp-config-sample.php wp-config.php

sudo sed -i "s/database_name_here/$DB_NAME/"   wp-config.php
sudo sed -i "s/username_here/$DB_USER/"         wp-config.php
sudo sed -i "s/password_here/$DB_PASS/"         wp-config.php

# Fetch and inject unique security keys from WordPress API
log "Fetching WordPress security keys..."
KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
if [[ -n "$KEYS" ]]; then
    # Remove the placeholder block and append real keys
    sudo sed -i "/define( 'AUTH_KEY'/,/define( 'NONCE_SALT'/d" wp-config.php
    echo "$KEYS" | sudo tee -a wp-config.php > /dev/null
    success "Security keys injected."
else
    warn "Could not fetch security keys — using defaults. Replace manually."
fi

# ==========================================
# SECTION 6 — Permissions
# ==========================================

log "Setting file permissions..."
sudo chown -R www-data:www-data /var/www/"$DOMAIN"
sudo chmod -R 755 /var/www/"$DOMAIN"
sudo chmod 640 /var/www/"$DOMAIN"/wp-config.php
success "Permissions set."

# ==========================================
# SECTION 7 — Apache Virtual Host
# ==========================================

log "Creating Apache virtual host..."
sudo bash -c "cat > /etc/apache2/sites-available/$DOMAIN.conf" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot /var/www/$DOMAIN

    <Directory /var/www/$DOMAIN>
        AllowOverride All
        Require all granted
        Options -Indexes
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>
EOF

sudo a2ensite "$DOMAIN.conf"
sudo a2enmod rewrite

log "Validating Apache configuration..."
sudo apache2ctl configtest && success "Apache config OK."

sudo systemctl restart apache2
success "Apache restarted with new virtual host."

# ==========================================
# SECTION 8 — Firewall (UFW)
# ==========================================

if [[ "$ENABLE_UFW" == "y" || "$ENABLE_UFW" == "Y" ]]; then
    log "Configuring UFW firewall..."
    sudo apt install ufw -y >> "$LOG_FILE" 2>&1
    sudo ufw allow OpenSSH
    sudo ufw allow 'Apache Full'
    sudo ufw --force enable
    success "UFW enabled — ports 22, 80, 443 open."
else
    warn "UFW skipped. Ensure your firewall allows ports 80 and 443."
fi

# ==========================================
# SECTION 9 — SSL with Certbot
# ==========================================

if [[ "$ENABLE_SSL" == "y" || "$ENABLE_SSL" == "Y" ]]; then
    log "Installing Certbot..."
    sudo apt install certbot python3-certbot-apache -y >> "$LOG_FILE" 2>&1

    warn "Note: SSL only works on real public domains, not .local domains."
    sudo certbot --apache -d "$DOMAIN" -d "www.$DOMAIN" && \
        success "SSL certificate installed for $DOMAIN." || \
        warn "Certbot failed — check domain DNS and try: sudo certbot --apache"
else
    warn "SSL skipped. Run 'sudo certbot --apache' when you have a real domain."
fi

# ==========================================
# SECTION 10 — Backup
# ==========================================

backup_site() {
    BACKUP_DIR="/backup"
    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

    log "Creating backup..."
    sudo mkdir -p "$BACKUP_DIR"

    sudo tar -czf "$BACKUP_DIR/${DOMAIN}-files-${TIMESTAMP}.tar.gz" /var/www/"$DOMAIN" \
        >> "$LOG_FILE" 2>&1
    sudo mysqldump -u root "$DB_NAME" \
        > "$BACKUP_DIR/${DOMAIN}-db-${TIMESTAMP}.sql"

    success "Backup saved to $BACKUP_DIR/"
    echo -e "  Files : ${BACKUP_DIR}/${DOMAIN}-files-${TIMESTAMP}.tar.gz"
    echo -e "  DB    : ${BACKUP_DIR}/${DOMAIN}-db-${TIMESTAMP}.sql"
}

if [[ "$DO_BACKUP" == "y" || "$DO_BACKUP" == "Y" ]]; then
    backup_site
fi

# ==========================================
# SECTION 11 — Summary
# ==========================================

log "Deployment completed successfully for $DOMAIN"

echo -e "${GREEN}"
echo "============================================"
echo "  WordPress Deployed Successfully!"
echo "============================================"
echo -e "${NC}"
echo -e "  Domain    : http://$DOMAIN"
echo -e "  Files     : /var/www/$DOMAIN"
echo -e "  DB Name   : $DB_NAME"
echo -e "  DB User   : $DB_USER"
echo -e "  Log File  : $LOG_FILE"
echo ""
echo -e "${YELLOW}  Next: Visit http://$DOMAIN to complete WordPress setup.${NC}"
echo ""
