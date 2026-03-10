# Open WebUI & Xray Deployment

Deploy [Open WebUI](https://github.com/open-webui/open-webui) and [Xray](https://github.com/XTLS/Xray-core) using one of two approaches:

| Approach | Best for | TLS | Auto-update |
|---|---|---|---|
| **Option A** — VM + Docker Compose | Full control, single VM | Let's Encrypt via Certbot | Watchtower |
| **Option B** — Azure Container Apps | Serverless, zero infra management | Built-in (managed by Azure) | Re-run deploy script |

---

## Option A: VM + Docker Compose

Run all services on a single VM with Nginx as a reverse proxy, Certbot for free TLS certificates, and Watchtower for automatic image updates.

### Architecture

```
Internet
  │
  ├─ :443 ──► Nginx ──► Open WebUI (:8080)
  │              │
  │              └────► Certbot (certificate renewal)
  │
  └─ :8443 ─► Xray (VLESS + WS + TLS)
```

### Services

| Service | Image | Purpose |
|---|---|---|
| **nginx** | `nginx:latest` | Reverse proxy & TLS termination (ports 80/443) |
| **open-webui** | `ghcr.io/open-webui/open-webui:main` | AI chat web interface |
| **xray** | `ghcr.io/xtls/xray-core:latest` | VLESS proxy (port 8443) |
| **certbot** | `certbot/certbot:latest` | Auto-obtain Let's Encrypt certificates |
| **watchtower** | `containrrr/watchtower:latest` | Auto-update labeled containers every 24h |

### Prerequisites

- A VM (Linux) with Docker and Docker Compose installed
- A domain name with DNS A record pointing to the VM's public IP
- Ports 80, 443, and 8443 open in the firewall / security group

### Directory Structure

```
project/
├── docker-compose.yml
├── nginx/
│   ├── conf/          # Nginx site configs (*.conf)
│   └── logs/          # Nginx access & error logs
├── xray/
│   ├── config.json    # Xray configuration
│   └── logs/          # Xray logs
└── certbot/
    ├── www/           # ACME challenge webroot
    └── conf/          # TLS certificates
```

### Quick Start

```bash
# 1. Clone or copy files to the VM
scp -r ./ user@your-vm-ip:~/project/

# 2. SSH into the VM
ssh user@your-vm-ip
cd ~/project

# 3. Set your domain and create the Nginx config
export DOMAIN="example.com"

# 4. Prepare Xray config (replace <uuid> with your own)
cat > xray/config.json << 'EOF'
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 8443,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "<uuid>", "level": 0 }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": { "path": "/ws" }
    }
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF

# 5. Obtain TLS certificate (first run)
docker compose run --rm certbot

# 6. Start all services
docker compose up -d
```

### Certificate Renewal

Certbot certificates expire every 90 days. Add a cron job for auto-renewal:

```bash
# Renew certs and reload Nginx every day at 3:00 AM
0 3 * * * cd ~/project && docker compose run --rm certbot renew && docker compose exec nginx nginx -s reload
```

### Common Operations

```bash
# View logs
docker compose logs -f open-webui
docker compose logs -f xray

# Restart a single service
docker compose restart open-webui

# Force update images
docker compose pull && docker compose up -d

# Stop everything
docker compose down
```

---

## Option B: Azure Container Apps

One-click deployment via Azure CLI shell scripts. Each script supports three execution modes:

| Mode | Command | Behavior |
|---|---|---|
| `auto` (default) | `bash script.sh` | Creates resources if missing; skips/updates if they exist |
| `create` | `bash script.sh create` | Force-creates all resources |
| `update` | `bash script.sh update` | Updates the Container App only |

### Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed and authenticated (`az login`)
- Bash environment (Linux / macOS / WSL / Git Bash)

---

### deploy-openwebui.sh

Deploys Open WebUI on Azure Container Apps with a PostgreSQL Flexible Server and Azure File persistent storage.

#### Provisioned Resources

| Resource | Description |
|---|---|
| Resource Group | Logical container for all resources |
| Container Apps Environment | Managed environment for container apps |
| PostgreSQL Flexible Server | Burstable B1ms tier, 32 GB storage |
| Storage Account + File Share | Persistent volume for `/app/backend/data/uploads` |
| Container App | Open WebUI container (1 CPU / 2 Gi memory) |

#### Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `PG_ADMIN_USER` | **Yes** | — | PostgreSQL admin username |
| `PG_ADMIN_PASSWORD` | **Yes** | — | PostgreSQL admin password |
| `RESOURCE_GROUP` | No | `open-webui-rg` | Resource group name |
| `LOCATION` | No | `japaneast` | Azure region |
| `ENVIRONMENT_NAME` | No | `open-webui-env` | Container Apps environment name |
| `APP_NAME` | No | `open-webui` | Container app name |
| `STORAGE_ACCOUNT_NAME` | No | `openwebuistore` | Storage account name |
| `PG_SERVER_NAME` | No | `open-webui-pg` | PostgreSQL server name |
| `PG_DB_NAME` | No | `openwebui` | Database name |

#### Usage

```bash
export PG_ADMIN_USER="myadmin"
export PG_ADMIN_PASSWORD="YourStrongPassword123!"
bash deploy-openwebui.sh
```

#### Common Operations

```bash
# Stream logs
az containerapp logs show -n open-webui -g open-webui-rg --follow

# Update image
bash deploy-openwebui.sh update

# Delete all resources
az group delete --name open-webui-rg --yes --no-wait
```

---

### deploy-xray.sh

Deploys Xray (VLESS + WebSocket + TLS) on Azure Container Apps.

#### Provisioned Resources

| Resource | Description |
|---|---|
| Resource Group | Logical container for all resources |
| Container Apps Environment | Managed environment for container apps |
| Container App | Xray container (0.25 CPU / 0.5 Gi memory) |

#### Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `XRAY_UUID` | **Yes** | — | VLESS user UUID (generate with `uuidgen`) |
| `WS_PATH` | No | `/ws` | WebSocket path |
| `RESOURCE_GROUP` | No | `xray-rg` | Resource group name |
| `LOCATION` | No | `japaneast` | Azure region |
| `ENVIRONMENT_NAME` | No | `xray-env` | Container Apps environment name |
| `APP_NAME` | No | `xray` | Container app name |

#### Usage

```bash
export XRAY_UUID="$(uuidgen)"
bash deploy-xray.sh
```

On completion, the script prints the access URL and a ready-to-use VLESS link.

#### Common Operations

```bash
# Stream logs
az containerapp logs show -n xray -g xray-rg --follow

# Delete all resources
az group delete --name xray-rg --yes --no-wait
```

---

## Comparison

| | VM + Docker Compose | Azure Container Apps |
|---|---|---|
| **Infra management** | You manage the VM, OS updates, firewall | Fully managed by Azure |
| **Cost model** | Fixed VM cost | Pay-per-use (consumption plan) |
| **TLS** | Let's Encrypt (Certbot, manual renewal) | Built-in, auto-renewed |
| **Auto-update** | Watchtower (watches labeled containers) | Re-run `bash script.sh update` |
| **Scaling** | Manual (resize VM) | Auto-scale via `minReplicas` / `maxReplicas` |
| **Database** | Bring your own (or add to Compose) | Managed PostgreSQL Flexible Server |
| **Best for** | Full control, custom networking | Fast setup, minimal ops overhead |
