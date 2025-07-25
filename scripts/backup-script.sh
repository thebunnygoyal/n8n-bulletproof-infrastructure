#!/bin/bash

# N8N BULLETPROOF BACKUP SCRIPT
# Prevents workflow loss through multi-layer backup strategy

set -e

# Configuration
STORAGE_ACCOUNT="n8nstorageneural"
BACKUP_STORAGE="n8nbackupneural"
RESOURCE_GROUP="rg-rishavgoyalofficial-5955_ai"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="/tmp/n8n-backup-${DATE}"

echo "🚀 Starting N8N Bulletproof Backup Process..."

# Layer 1: Azure File Share Snapshot
echo "📸 Creating Azure File Share Snapshot..."
az storage share snapshot \
  --account-name $STORAGE_ACCOUNT \
  --name n8n-data \
  --output table

# Layer 2: Download and backup database
echo "💾 Downloading current database..."
mkdir -p $BACKUP_DIR
az storage file download \
  --account-name $STORAGE_ACCOUNT \
  --share-name n8n-data \
  --path database.sqlite \
  --dest "${BACKUP_DIR}/database.sqlite"

# Layer 3: Download configuration files
echo "⚙️ Backing up configuration..."
az storage file download-batch \
  --account-name $STORAGE_ACCOUNT \
  --source n8n-data \
  --destination "${BACKUP_DIR}/config" \
  --pattern ".n8n/*"

# Layer 4: Export workflows via API (if n8n is running)
echo "📋 Exporting workflows via API..."
N8N_URL="https://n8n-neural-mcp.wonderfulrock-519a3fc8.eastus2.azurecontainerapps.io"
curl -X GET "${N8N_URL}/api/v1/workflows" \
  -H "Content-Type: application/json" \
  > "${BACKUP_DIR}/workflows-export.json" 2>/dev/null || echo "⚠️ API export failed (server may be down)"

# Layer 5: Upload to backup storage account
echo "☁️ Uploading to backup storage..."
az storage container create \
  --account-name $BACKUP_STORAGE \
  --name "n8n-backups" \
  --public-access off

# Create backup archive
cd $BACKUP_DIR
tar -czf "n8n-backup-${DATE}.tar.gz" ./*

# Upload to backup storage
az storage blob upload \
  --account-name $BACKUP_STORAGE \
  --container-name n8n-backups \
  --name "n8n-backup-${DATE}.tar.gz" \
  --file "n8n-backup-${DATE}.tar.gz"

# Layer 6: Git backup (if repository exists)
if [ -d "/tmp/n8n-workflows" ]; then
  echo "📚 Committing to Git repository..."
  cd /tmp/n8n-workflows
  cp "${BACKUP_DIR}/workflows-export.json" "backups/${DATE}/"
  git add .
  git commit -m "Automated backup: ${DATE}"
  git push origin main
fi

# Cleanup
rm -rf $BACKUP_DIR

echo "✅ Backup completed successfully!"
echo "📊 Backup Details:"
echo "   - Snapshot: Created in Azure Files"
echo "   - Archive: n8n-backup-${DATE}.tar.gz"
echo "   - Location: ${BACKUP_STORAGE}/n8n-backups/"
echo "   - Git: Committed to repository (if configured)"

# Layer 7: Health Check
echo "🔍 Performing health check..."
curl -f $N8N_URL/healthz > /dev/null 2>&1 && echo "✅ N8N Server: Healthy" || echo "❌ N8N Server: Not responding"

echo "🎯 Backup process completed at $(date)"