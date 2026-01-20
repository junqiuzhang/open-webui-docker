# OpenWebUI + Xray Docker Config

## Description
This docker compose file is used to deploy the OpenWebUI application with Xray proxy. It contains the following services:
- **OpenWebUI**: The main application
- **Nginx**: Reverse proxy for the OpenWebUI application (port 443)
- **Xray**: VLESS + REALITY proxy server (port 8443)
- **Certbot**: SSL certificate management
- **Watchtower**: Automatic updates for containers

## Usage
### 1. Create directories
```bash
mkdir -p nginx/conf nginx/logs certbot/conf certbot/www xray
```

### 2. Copy configuration files
- Copy nginx/default.conf to nginx/conf/default.conf
- Copy xray/config.json to xray/config.json

### 3. Generate Xray keys (optional, if creating new config)
```bash
# Generate X25519 key pair
docker run --rm ghcr.io/xtls/xray-core:latest x25519

# Generate UUID
docker run --rm ghcr.io/xtls/xray-core:latest uuid

# Generate Short ID
openssl rand -hex 8
```

### 4. Start services
```bash
docker-compose up -d
```

### 5. Get SSL certificate (first time only)
```bash
docker-compose run --rm certbot
```

### 6. Open firewall ports
- 80: HTTP (redirect to HTTPS)
- 443: HTTPS (OpenWebUI)
- 8443: Xray REALITY

## Xray Client Configuration
| Item | Value |
|------|-------|
| Address | `<your_domain>` |
| Port | `8443` |
| Protocol | VLESS |
| UUID | `<your_uuid>` |
| Flow | xtls-rprx-vision |
| Transport | tcp |
| Security | reality |
| SNI | www.microsoft.com |
| Fingerprint | chrome |
| Public Key | `<your_public_key>` |
| Short ID | `<your_short_id>` |

### VLESS Share Link Format
```
vless://<uuid>@<domain>:8443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=<public_key>&sid=<short_id>&type=tcp#<name>
```

## Useful Commands
```bash
# View logs
docker logs nginx
docker logs xray
docker logs open-webui

# Restart services
docker-compose restart

# Rebuild and restart
docker-compose down
docker-compose up -d

# Renew SSL certificate
docker-compose run --rm certbot renew
```
