#!/bin/bash
# ============================================================
# Azure Container App (Xray) One-Click Deploy / Update
# Usage:
#   export XRAY_UUID="your-uuid-here"
#   export WS_PATH="/your/ws/path"        # Optional, defaults to /ws
#   bash deploy-xray.sh          # Auto-detect: create if missing, update if exists
#   bash deploy-xray.sh create   # Force-create all resources
#   bash deploy-xray.sh update   # Update Container App only
# ============================================================

set -euo pipefail

# ==================== Configuration ====================
RESOURCE_GROUP="${RESOURCE_GROUP:-xray-rg}"
LOCATION="${LOCATION:-japaneast}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-xray-env}"
APP_NAME="${APP_NAME:-xray}"

# Xray config (sensitive values read from env vars)
XRAY_UUID="${XRAY_UUID:?Error: please set XRAY_UUID env var (generate with uuidgen)}"
WS_PATH="${WS_PATH:-/ws}"
# ================================================

MODE="${1:-auto}"  # auto / create / update

# --- Helper functions ---
resource_exists() {
  az "$1" show "${@:2}" --query "id" -o tsv 2>/dev/null && return 0 || return 1
}

# --- Step 1: Resource Group ---
if [[ "$MODE" == "create" ]] || [[ "$MODE" == "auto" ]] && ! resource_exists group --name "$RESOURCE_GROUP"; then
  echo "[1/5] Creating resource group $RESOURCE_GROUP..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none
else
  echo "[1/5] Resource group $RESOURCE_GROUP already exists, skipping"
fi

# --- Step 2: Container Apps Environment ---
if [[ "$MODE" == "create" ]] || [[ "$MODE" == "auto" ]] && ! resource_exists containerapp env --name "$ENVIRONMENT_NAME" --resource-group "$RESOURCE_GROUP"; then
  echo "[2/5] Creating Container Apps environment $ENVIRONMENT_NAME..."
  az containerapp env create \
    --name "$ENVIRONMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    -o none
else
  echo "[2/5] Environment $ENVIRONMENT_NAME already exists, skipping"
fi

# --- Step 3: Get environment ID ---
echo "[3/5] Getting environment ID..."
ENV_ID=$(az containerapp env show \
  --name "$ENVIRONMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "id" -o tsv)
echo "       Environment ID: $ENV_ID"

# --- Step 4: Generate YAML ---
echo "[4/5] Generating Xray config and container-app.yaml..."
XRAY_CONFIG="{\"log\":{\"loglevel\":\"warning\"},\"inbounds\":[{\"port\":8080,\"protocol\":\"vless\",\"settings\":{\"clients\":[{\"id\":\"${XRAY_UUID}\",\"level\":0}],\"decryption\":\"none\"},\"streamSettings\":{\"network\":\"ws\",\"wsSettings\":{\"path\":\"${WS_PATH}\"}}}],\"outbounds\":[{\"protocol\":\"freedom\",\"tag\":\"direct\"}]}"

cat > container-app.yaml << YAMLEOF
type: Microsoft.App/containerApps
location: ${LOCATION}
properties:
  managedEnvironmentId: ${ENV_ID}
  configuration:
    ingress:
      external: true
      targetPort: 8080
      transport: auto
      allowInsecure: false
    secrets:
      - name: xray-config
        value: '${XRAY_CONFIG}'
  template:
    containers:
      - name: xray
        image: ghcr.io/xtls/xray-core:latest
        resources:
          cpu: 0.25
          memory: 0.5Gi
        volumeMounts:
          - volumeName: xray-config-vol
            mountPath: /usr/local/etc/xray
    volumes:
      - name: xray-config-vol
        storageType: Secret
        secrets:
          - secretRef: xray-config
            path: config.json
    scale:
      minReplicas: 1
      maxReplicas: 1
YAMLEOF

echo "       Generated container-app.yaml"

# --- Step 5: Create or update Container App ---
if [[ "$MODE" == "update" ]]; then
  echo "[5/5] Updating Container App..."
  az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --yaml container-app.yaml -o none
elif resource_exists containerapp --name "$APP_NAME" --resource-group "$RESOURCE_GROUP"; then
  echo "[5/5] Container App already exists, updating..."
  az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --yaml container-app.yaml -o none
else
  echo "[5/5] Creating Container App..."
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
VLESS_LINK="vless://${XRAY_UUID}@${FQDN}:443?encryption=none&type=ws&host=${FQDN}&path=$(echo "$WS_PATH" | sed 's|/|%2F|g')&security=tls&sni=${FQDN}#Azure-Xray"
echo "VLESS 链接: $VLESS_LINK"
