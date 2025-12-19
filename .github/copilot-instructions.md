# Copilot Instructions for fewohbee-dockerized

## Project Overview

This is a Docker Compose orchestration for deploying [fewohbee](https://github.com/developeregrem/fewohbee) (a guesthouse administration tool). It's an infrastructure-as-code project that provides a complete production environment with automated SSL, backups, and updates.

### Architecture

**Service Stack** ([docker-compose.yml](docker-compose.yml)):
- **nginx** (mainline-alpine): Reverse proxy handling HTTP/HTTPS on ports 80/443
- **php** (developeregrem/fewohbee-phpfpm): PHP 8.4-fpm running Symfony app, auto-installs fewohbee on first run
- **mariadb** (11.6): Database with automated backup support
- **redis** (alpine): Session/cache store when APP_ENV=redis (production mode)
- **acme** (developeregrem/fewohbee-acme): Certificate management (Let's Encrypt or self-signed)

All services communicate via `internal-network` bridge network. The application is installed into shared volume `feb-data` by the php container on startup.

### Key Configuration Patterns

**Environment-driven deployment**: `.env` file (generated from [.env.dist](.env.dist)) controls all configuration:
- Database credentials auto-generated during installation
- `APP_ENV=redis` (production) vs `dev` changes caching behavior
- `SELF_SIGNED=true` XOR `LETSENCRYPT=true` determines certificate type
- `WEB_HOST=http://web:8080` points to internal nginx vhost for PDF generation

**Volume strategy**:
- `feb-data`: Shared across web/php/acme for application code and SSL certificates
- `db-vol`: MariaDB persistent storage
- `${WWW_ROOT}` (default: `../data`): Host mount for user data persistence

## Critical Workflows

### Installation & Setup

**Never edit `.env` directly - always regenerate**:
```bash
./install.sh  # Interactive wizard that creates .env from .env.dist
```

Installation flow ([install.sh](install.sh) L1-237):
1. Validates Docker and openssl are available
2. Prompts for hostname, SSL mode (self-signed/letsencrypt), cron setup, locale (de/en)
3. Generates secure passwords with openssl (MariaDB root, user, backup user, APP_SECRET)
4. Runs `docker compose up -d` and waits for php container to complete first-run setup
5. Creates backup user in MariaDB with `GRANT LOCK TABLES, SELECT` permissions
6. Loads initial fixtures and optionally test data

**Post-installation**: Cron jobs are symlinked to `/etc/cron.d/` (requires root access)

### Database Backups

**Two-layer backup system**:
1. **Cron trigger** ([cron.d/backup_mysql_docker](cron.d/backup_mysql_docker)): Daily at 3 AM, runs [backup-db.sh](backup-db.sh)
2. **Container execution**: Shell script enters db container and executes [data/db/backup_mysql_cron.sh](data/db/backup_mysql_cron.sh)
3. **Backup process** (inside container):
   - Runs `mariadb-upgrade` to handle version upgrades before backup
   - Uses `mariadb-dump -c -n -R` (complete-insert, if-exists, stored procedures)
   - Creates 7 rotating daily backups: `fewohbee_{1-7}.sql` (1=Monday)
   - Compresses to `mysql_{1-7}.tar.gz` and copies to `/dbbackup` (mapped to `${MYSQL_BACKUP_FOLDER}`)

**Restore from backup**: Extract .tar.gz from `${MYSQL_BACKUP_FOLDER}` and import SQL file into db container

### Container Updates

**Automated weekly updates** ([cron.d/update-docker](cron.d/update-docker)): Every Monday 4 AM via [update-docker.sh](update-docker.sh)
```bash
docker compose pull          # Get latest images
docker compose build --force-rm --pull
docker compose stop
docker compose up --force-recreate -d
docker image prune -f        # Clean dangling images
```

**Manual version control**: Set `FEWOHBEE_VERSION` in `.env` to pin specific app version (default: `latest`)

### SSL Certificate Management

**Handled by acme container** ([docker-compose.yml](docker-compose.yml#L70-L89)):
- Runs `./run.sh` on startup to provision/renew certificates
- Stores certificates in `certs-vol`, mounted read-only by nginx
- For Let's Encrypt: Supports DynDNS integration with desec.io (`DYNDNS_PROVIDER`, `DEDYN_TOKEN`, `DEDYN_NAME`)
- Nginx serves ACME challenges via [site-enabled-http/00_acme.snippet](conf/nginx/site-enabled-http/00_acme.snippet) and [site-enabled-https/00_acme.snippet](conf/nginx/site-enabled-https/00_acme.snippet)

**Certificate renewal**: Automatic via acme container cron jobs

### Nginx Configuration Structure

**Dynamic server_name**: [conf/nginx/site.conf](conf/nginx/site.conf#L13) includes `server_name.active`, generated from [templates/server_name.template](conf/nginx/templates/server_name.template) via `envsubst` in nginx command

**Three server blocks**:
1. Port 80: Redirects all HTTP to HTTPS (includes ACME challenge snippets)
2. Port 443: Main HTTPS entry point, includes [snippets/sslconf.snippet](conf/nginx/snippets/sslconf.snippet) and site-specific configs
3. Port 8080: Internal-only for PDF generation (accessed via `WEB_HOST`)

**Security headers**: Applied via [snippets/header.snippet](conf/nginx/snippets/header.snippet) (X-Content-Type-Options, X-Frame-Options)

## Development Patterns

### Script Conventions

- **Shebang**: Use `#!/bin/bash` for complex scripts, `#!/bin/sh` for simple Alpine-compatible scripts
- **Docker binary detection**: Always use `$(which docker)` to get path dynamically (see [backup-db.sh](backup-db.sh#L3))
- **Working directory**: Scripts use `cd "$(dirname "$0")"` to ensure correct execution path
- **Error handling**: Use `if [ $? -ne 0 ]` to check command status before proceeding

### Modifying Configuration

**Add new environment variables**:
1. Add to [.env.dist](.env.dist) with placeholder value
2. Update [install.sh](install.sh) to prompt/generate value (use `sed` for substitution pattern)
3. Reference in [docker-compose.yml](docker-compose.yml) environment section

**Add nginx config**: Place snippet in `conf/nginx/site-enabled-http/` or `site-enabled-https/` (auto-included)

### Debugging

**View container logs**:
```bash
docker compose logs -f php      # Application logs
docker compose logs -f web      # Nginx access/error logs
docker compose logs -f acme     # Certificate management
```

**Access containers**:
```bash
docker compose exec php /bin/sh
docker compose exec --user www-data php /bin/sh  # Run as web user
docker compose exec db mariadb -uroot -p$MARIADB_ROOT_PASSWORD
```

**Check application status**: Wait for `/firstrun` file in php container to contain "1" ([install.sh](install.sh#L206))

### Testing Changes

**Full environment reset** ([cleanup.sh](cleanup.sh)):
```bash
./cleanup.sh  # WARNING: Destroys all volumes and containers
```

**Re-run installation**: Delete `.env` file and run `./install.sh` again
