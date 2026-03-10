#!/bin/bash
# ============================================================
# Azure Container App (Open WebUI) One-Click Deploy / Update
# Usage:
#   export PG_ADMIN_PASSWORD="YourStrongPassword123!"
#   bash deploy-openwebui.sh          # Auto-detect: create if missing, update if exists
#   bash deploy-openwebui.sh create   # Force-create all resources
#   bash deploy-openwebui.sh update   # Update Container App only
# ============================================================

set -euo pipefail

# ==================== Configuration ====================
RESOURCE_GROUP="${RESOURCE_GROUP:-open-webui-rg}"
LOCATION="${LOCATION:-japaneast}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-open-webui-env}"
APP_NAME="${APP_NAME:-open-webui}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-openwebuistore}"
SHARE_NAME="open-webui-data"
STORAGE_ENV_NAME="openwebuifiles"

# PostgreSQL config (sensitive values read from env vars)
PG_SERVER_NAME="${PG_SERVER_NAME:-open-webui-pg}"
PG_ADMIN_USER="${PG_ADMIN_USER:?Error: please set PG_ADMIN_USER env var}"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:?Error: please set PG_ADMIN_PASSWORD env var}"
PG_DB_NAME="${PG_DB_NAME:-openwebui}"
PG_SKU="Standard_B1ms"  # Lowest tier: 1 vCore, 2 GiB RAM

IMAGE="ghcr.io/open-webui/open-webui:main"
CPU="1.0"
MEMORY="2.0Gi"
TARGET_PORT=8080
# ================================================

MODE="${1:-auto}"  # auto / create / update

# --- Helper functions ---
resource_exists() {
  az "$1" show "${@:2}" --query "id" -o tsv 2>/dev/null && return 0 || return 1
}

storage_account_exists() {
  az storage account show --name "$1" --resource-group "$2" --query "id" -o tsv 2>/dev/null && return 0 || return 1
}

containerapp_env_exists() {
  az containerapp env show --name "$1" --resource-group "$2" --query "id" -o tsv 2>/dev/null && return 0 || return 1
}

env_storage_exists() {
  az containerapp env storage show --name "$1" --resource-group "$2" --storage-name "$3" --query "name" -o tsv 2>/dev/null && return 0 || return 1
}

# --- Step 1: Resource Group ---
if [[ "$MODE" == "create" ]] || [[ "$MODE" == "auto" ]] && ! resource_exists group --name "$RESOURCE_GROUP"; then
  echo "[1/9] Creating resource group $RESOURCE_GROUP..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none
else
  echo "[1/9] Resource group $RESOURCE_GROUP already exists, skipping"
fi

# --- Step 2: Container Apps Environment ---
if [[ "$MODE" == "create" ]] || [[ "$MODE" == "auto" ]] && ! containerapp_env_exists "$ENVIRONMENT_NAME" "$RESOURCE_GROUP"; then
  echo "[2/9] Creating Container Apps environment $ENVIRONMENT_NAME..."
  az containerapp env create \
    --name "$ENVIRONMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    -o none
else
  echo "[2/9] Environment $ENVIRONMENT_NAME already exists, skipping"
fi

# --- Step 3: Register PostgreSQL resource provider & create Flexible Server ---
pg_server_exists() {
  az postgres flexible-server show --name "$1" --resource-group "$2" --query "id" -o tsv 2>/dev/null && return 0 || return 1
}

if [[ "$MODE" == "create" ]] || [[ "$MODE" == "auto" ]] && ! pg_server_exists "$PG_SERVER_NAME" "$RESOURCE_GROUP"; then
  echo "[3/9] Registering Microsoft.DBforPostgreSQL resource provider..."
  az provider register --namespace Microsoft.DBforPostgreSQL --wait -o none
  echo "       Creating PostgreSQL Flexible Server $PG_SERVER_NAME (may take a few minutes)..."
  az postgres flexible-server create \
    --name "$PG_SERVER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --admin-user "$PG_ADMIN_USER" \
    --admin-password "$PG_ADMIN_PASSWORD" \
    --tier Burstable \
    --sku-name "$PG_SKU" \
    --storage-size 32 \
    --version 16 \
    --yes \
    -o none
else
  echo "[3/9] PostgreSQL $PG_SERVER_NAME already exists, skipping"
fi

# --- Step 4: Configure PostgreSQL firewall (allow Azure services) ---
echo "[4/9] Configuring PostgreSQL firewall rules..."
az postgres flexible-server firewall-rule create \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --rule-name "AllowAzureServices" \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0 \
  -o none 2>/dev/null || true

# Create database
az postgres flexible-server db create \
  --server-name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --database-name "$PG_DB_NAME" \
  -o none 2>/dev/null || true

PG_FQDN=$(az postgres flexible-server show \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "fullyQualifiedDomainName" -o tsv)
DATABASE_URL="postgresql://${PG_ADMIN_USER}:${PG_ADMIN_PASSWORD}@${PG_FQDN}:5432/${PG_DB_NAME}"
echo "       PostgreSQL FQDN: $PG_FQDN"

# --- Step 5: Create Storage Account ---
if [[ "$MODE" == "create" ]] || [[ "$MODE" == "auto" ]] && ! storage_account_exists "$STORAGE_ACCOUNT_NAME" "$RESOURCE_GROUP"; then
  echo "[5/9] Creating storage account $STORAGE_ACCOUNT_NAME..."
  az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    -o none
else
  echo "[5/9] Storage account $STORAGE_ACCOUNT_NAME already exists, skipping"
fi

STORAGE_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].value" -o tsv)

# --- Step 6: Create File Share ---
if [[ "$MODE" == "create" ]] || [[ "$MODE" == "auto" ]]; then
  echo "[6/9] Ensuring Azure File Share $SHARE_NAME exists..."
  az storage share create \
    --name "$SHARE_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_KEY" \
    -o none
else
  echo "[6/9] Skipping file share creation (update mode)"
fi

# --- Step 7: Mount storage to environment ---
if [[ "$MODE" == "create" ]] || [[ "$MODE" == "auto" ]] && ! env_storage_exists "$ENVIRONMENT_NAME" "$RESOURCE_GROUP" "$STORAGE_ENV_NAME"; then
  echo "[7/9] Mounting storage to Container Apps environment..."
  az containerapp env storage set \
    --name "$ENVIRONMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --storage-name "$STORAGE_ENV_NAME" \
    --azure-file-account-name "$STORAGE_ACCOUNT_NAME" \
    --azure-file-account-key "$STORAGE_KEY" \
    --azure-file-share-name "$SHARE_NAME" \
    --access-mode ReadWrite \
    -o none
else
  echo "[7/9] Environment storage $STORAGE_ENV_NAME already exists, skipping"
fi

# --- Step 8: Get environment ID & generate YAML ---
echo "[8/9] Generating container-app.yaml..."
ENV_ID=$(az containerapp env show \
  --name "$ENVIRONMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "id" -o tsv)
echo "       Environment ID: $ENV_ID"

cat > container-app.yaml << YAMLEOF
type: Microsoft.App/containerApps
location: ${LOCATION}
properties:
  managedEnvironmentId: ${ENV_ID}
  configuration:
    ingress:
      external: true
      targetPort: ${TARGET_PORT}
      transport: auto
      allowInsecure: false
    secrets:
      - name: database-url
        value: '${DATABASE_URL}'
  template:
    containers:
      - name: open-webui
        image: ${IMAGE}
        resources:
          cpu: ${CPU}
          memory: ${MEMORY}
        env:
          - name: DATABASE_URL
            secretRef: database-url
        probes:
          - type: startup
            httpGet:
              path: /health
              port: ${TARGET_PORT}
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 30
            timeoutSeconds: 5
          - type: liveness
            httpGet:
              path: /health
              port: ${TARGET_PORT}
            periodSeconds: 30
            failureThreshold: 3
            timeoutSeconds: 5
        volumeMounts:
          - volumeName: open-webui-volume
            mountPath: /app/backend/data/uploads
    volumes:
      - name: open-webui-volume
        storageName: ${STORAGE_ENV_NAME}
        storageType: AzureFile
    scale:
      minReplicas: 1
      maxReplicas: 1
YAMLEOF

echo "       Generated container-app.yaml"

# --- Step 9: Create or update Container App ---
if [[ "$MODE" == "update" ]]; then
  echo "[9/9] Updating Container App..."
  az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --yaml container-app.yaml -o none
elif resource_exists containerapp --name "$APP_NAME" --resource-group "$RESOURCE_GROUP"; then
  echo "[9/9] Container App already exists, updating..."
  az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --yaml container-app.yaml -o none
else
  echo "[9/9] Creating Container App..."
  az containerapp create \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --yaml container-app.yaml -o none
fi

# --- Output ---
echo ""
echo "===== Deployment Complete ====="
FQDN=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "properties.configuration.ingress.fqdn" -o tsv)
echo "URL: https://$FQDN"
echo ""
echo "Storage account: $STORAGE_ACCOUNT_NAME"
echo ""
echo "Common operations:"
echo "  # View logs"
echo "  az containerapp logs show -n $APP_NAME -g $RESOURCE_GROUP --follow"
echo "  # Update image"
echo "  bash deploy-openwebui.sh update"
echo "  # Delete all resources"
echo "  az group delete --name $RESOURCE_GROUP --yes --no-wait"
