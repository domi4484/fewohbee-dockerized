# Deploying fewohbee as Subdomain with Existing Nginx

This guide explains how to deploy fewohbee on `reservations.gotthardhub.ch` when you already have nginx + certbot managing SSL on the host.

## Prerequisites

- Existing nginx + certbot setup on host
- DNS A record for `reservations.gotthardhub.ch` pointing to your server
- Docker and docker-compose installed

## Step 1: Update SSL Certificate

Add the new subdomain to your existing Let's Encrypt certificate:

```bash
sudo certbot --nginx -d gotthardhub.ch -d www.gotthardhub.ch -d reservations.gotthardhub.ch
```

Certbot will:
- Detect your existing certificate
- Add the new subdomain to it
- Automatically reload nginx

Verify the certificate includes all domains:
```bash
sudo certbot certificates
```

## Step 2: Modify fewohbee Docker Setup

The default fewohbee-dockerized setup binds nginx to ports 80/443, which conflicts with your host nginx. You need to:

1. **Use the modified docker-compose**: Copy `docker-compose.subdomain.yml` to `docker-compose.yml` (or use `-f` flag)
2. **Modify .env.dist**: Set `SELF_SIGNED=false` and `LETSENCRYPT=false` since SSL is handled by host
3. **Run installation**: `./install.sh` (select "no" for certificate options if prompted)

Key changes in the modified setup:
- nginx container exposes port **8083** instead of 80/443
- No SSL configuration in docker nginx (plain HTTP only)
- Removed acme container (not needed)
- nginx serves HTTP on 8083, proxies to PHP-FPM

## Step 3: Configure Host Nginx

Add this configuration to your host nginx for the subdomain:

```nginx
# /etc/nginx/sites-available/reservations.gotthardhub.ch
server {
    listen 164.90.160.108:443 ssl http2;
    server_name reservations.gotthardhub.ch;

    access_log /var/log/nginx/reservations.access.log;
    error_log /var/log/nginx/reservations.error.log;

    # SSL certificates (managed by certbot)
    ssl_certificate /etc/letsencrypt/live/gotthardhub.ch/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/gotthardhub.ch/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Proxy to fewohbee docker nginx
    location / {
        proxy_pass http://127.0.0.1:8083;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        
        # Increase buffer sizes for large responses
        proxy_buffer_size 128k;
        proxy_buffers 16 64k;
        proxy_busy_buffers_size 256k;
    }
}

# HTTP to HTTPS redirect
server {
    listen 164.90.160.108:80;
    server_name reservations.gotthardhub.ch;
    return 301 https://$host$request_uri;
}
```

Enable the site:
```bash
sudo ln -s /etc/nginx/sites-available/reservations.gotthardhub.ch /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## Step 4: Deploy fewohbee

```bash
cd /opt/fewohbee-dockerized
./install.sh
```

During installation:
- Hostname: `reservations.gotthardhub.ch`
- SSL: Select "self-signed" but we won't use it (no SSL in docker)
- Enable backups: yes
- Enable updates: yes
- Environment: prod
- Language: de or en

## Step 5: Verify Deployment

1. Check containers are running:
   ```bash
   docker compose ps
   ```

2. Check nginx logs:
   ```bash
   docker compose logs web
   sudo tail -f /var/log/nginx/reservations.access.log
   ```

3. Access https://reservations.gotthardhub.ch in browser

## Troubleshooting

**Issue: 502 Bad Gateway**
- Check docker containers: `docker compose ps`
- Check docker nginx: `docker compose logs web`
- Verify port 8083 is listening: `netstat -tlnp | grep 8083`

**Issue: PHP errors**
- Check PHP logs: `docker compose logs php`
- Exec into container: `docker compose exec php /bin/sh`

**Issue: Database connection**
- Check MariaDB: `docker compose logs db`
- Verify DATABASE_URL in `.env`

**Issue: SSL certificate**
- Verify certificate: `sudo certbot certificates`
- Check nginx config: `sudo nginx -t`
- Reload nginx: `sudo systemctl reload nginx`

## Architecture Diagram

```
Internet
   ↓
Host Nginx (443/80) - certbot manages SSL
   ↓
Docker: nginx:8083 (plain HTTP)
   ↓
Docker: PHP-FPM:9000
   ↓
Docker: MariaDB:3306
Docker: Redis:6379
```

## Notes

- **WEB_HOST**: Must be set to `http://web:8080` in `.env` for PDF generation
- **Backups**: Will be stored in `../dbbackup` on host
- **Updates**: Cron job will update docker images weekly
- **Data**: WordPress and fewohbee data are separate; no conflicts
