# wordpress-auto-deploy
Automated WordPress deployment toolkit for Linux servers with Apache, MySQL, and virtual host configuration.

# WordPress Auto Deploy

A Bash-based automation tool to deploy a complete WordPress site on an Ubuntu server with Apache, MariaDB, and PHP.

## Features

- LAMP stack installation (Apache, MariaDB, PHP)
- Automatic MariaDB database and user creation
- WordPress download and setup
- Apache virtual host configuration
- WordPress configuration (wp-config.php automation)
- File permission management
- Basic logging system

## Requirements

- Ubuntu 22.04+
- sudo/root privileges
- Active internet connection

## Usage

```bash
chmod +x deploy.sh
sudo ./deploy.sh

