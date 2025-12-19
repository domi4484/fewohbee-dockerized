#!/bin/bash
# Quick setup script for subdomain deployment
# Run this BEFORE running install.sh

set -e

echo "=== Fewohbee Subdomain Deployment Setup ==="
echo ""
echo "This script prepares fewohbee for deployment as a subdomain"
echo "when you already have nginx + certbot on the host."
echo ""

# Check if .env already exists
if [ -f ".env" ]; then
    echo "ERROR: .env file already exists."
    echo "This setup must be run before installation."
    exit 1
fi

# Backup original files
echo "Step 1: Backing up original files..."
cp docker-compose.yml docker-compose.yml.original
cp conf/nginx/site.conf conf/nginx/site.conf.original

# Use subdomain versions
echo "Step 2: Switching to subdomain configurations..."
cp docker-compose.subdomain.yml docker-compose.yml
cp conf/nginx/site.subdomain.conf conf/nginx/site.conf

echo ""
echo "✓ Configuration files updated for subdomain deployment"
echo ""
echo "Next steps:"
echo "1. Update your SSL certificate on the host:"
echo "   sudo certbot --nginx -d gotthardhub.ch -d www.gotthardhub.ch -d reservations.gotthardhub.ch"
echo ""
echo "2. Run the installation:"
echo "   ./install.sh"
echo "   - Hostname: reservations.gotthardhub.ch"
echo "   - SSL: Choose 'self-signed' (not used but required by script)"
echo ""
echo "3. Add nginx config on host (see DEPLOYMENT_SUBDOMAIN.md)"
echo ""
echo "4. Enable and reload host nginx:"
echo "   sudo ln -s /etc/nginx/sites-available/reservations.gotthardhub.ch /etc/nginx/sites-enabled/"
echo "   sudo nginx -t"
echo "   sudo systemctl reload nginx"
echo ""
echo "See DEPLOYMENT_SUBDOMAIN.md for full instructions."
