# Azure Container App Deployment Scripts

Automated deployment scripts for **Open WebUI** and **Xray** on Azure Container Apps via Azure CLI. Both scripts support three modes: auto-detect, create, and update.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed and authenticated (`az login`)
- Bash environment (Linux / macOS / WSL / Git Bash)

---

## 1. deploy-openwebui.sh

Deploys [Open WebUI](https://github.com/open-webui/open-webui) on Azure Container Apps with a PostgreSQL database and Azure File persistent storage.

### Provisioned Resources

| Resource | Description |
|---|---|
| Resource Group | Logical container for all resources |
| Container Apps Environment | Managed environment for container apps |
| PostgreSQL Flexible Server | Burstable B1ms tier, 32 GB storage |
| Storage Account + File Share | Persistent volume for `/app/backend/data/uploads` |
| Container App | Open WebUI container (1 CPU / 2 Gi memory) |

### Environment Variables

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

### Usage

```bash
# First-time deployment
export PG_ADMIN_USER="myadmin"
export PG_ADMIN_PASSWORD="YourStrongPassword123!"
bash deploy-openwebui.sh

# Force re-create all resources
bash deploy-openwebui.sh create

# Update container app only (e.g. image upgrade)
bash deploy-openwebui.sh update
```

### Common Operations

```bash
# Stream logs
az containerapp logs show -n open-webui -g open-webui-rg --follow

# Delete all resources
az group delete --name open-webui-rg --yes --no-wait
```

---

## 2. deploy-xray.sh

Deploys [Xray](https://github.com/XTLS/Xray-core) (VLESS + WebSocket + TLS) on Azure Container Apps.

### Provisioned Resources

| Resource | Description |
|---|---|
| Resource Group | Logical container for all resources |
| Container Apps Environment | Managed environment for container apps |
| Container App | Xray container (0.25 CPU / 0.5 Gi memory) |

### Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `XRAY_UUID` | **Yes** | — | VLESS user UUID (generate with `uuidgen`) |
| `WS_PATH` | No | `/ws` | WebSocket path |
| `RESOURCE_GROUP` | No | `xray-rg` | Resource group name |
| `LOCATION` | No | `japaneast` | Azure region |
| `ENVIRONMENT_NAME` | No | `xray-env` | Container Apps environment name |
| `APP_NAME` | No | `xray` | Container app name |

### Usage

```bash
# First-time deployment
export XRAY_UUID="$(uuidgen)"
bash deploy-xray.sh

# Custom WebSocket path
export XRAY_UUID="your-uuid"
export WS_PATH="/custom/path"
bash deploy-xray.sh

# Update container app only
bash deploy-xray.sh update
```

On completion, the script prints the access URL and a ready-to-use VLESS link.

### Common Operations

```bash
# Stream logs
az containerapp logs show -n xray -g xray-rg --follow

# Delete all resources
az group delete --name xray-rg --yes --no-wait
```

---

## Execution Modes

Both scripts share the same three execution modes:

| Mode | Command | Behavior |
|---|---|---|
| `auto` (default) | `bash script.sh` | Creates resources if missing; skips/updates if they exist |
| `create` | `bash script.sh create` | Force-creates all resources |
| `update` | `bash script.sh update` | Updates the Container App only |
