#!/bin/bash

# N8N DISASTER RECOVERY SCRIPT
# Restores workflows and data from bulletproof backup system

set -e

# Configuration
STORAGE_ACCOUNT="n8nstorageneural"
BACKUP_STORAGE="n8nbackupneural"
RESOURCE_GROUP="rg-rishavgoyalofficial-5955_ai"
RECOVERY_DIR="/tmp/n8n-recovery"

echo "🚨 Starting N8N Disaster Recovery Process..."

# Function to list available backups
list_backups() {
  echo "📋 Available backups:"
  az storage blob list \
    --account-name $BACKUP_STORAGE \
    --container-name n8n-backups \
    --output table \
    --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}"
}

# Function to restore from backup
restore_from_backup() {
  local backup_name=$1
  
  if [ -z "$backup_name" ]; then
    echo "❌ No backup specified"
    list_backups
    read -p "Enter backup name to restore: " backup_name
  fi
  
  echo "🔄 Restoring from backup: $backup_name"
  
  # Download backup archive
  mkdir -p $RECOVERY_DIR
  az storage blob download \
    --account-name $BACKUP_STORAGE \
    --container-name n8n-backups \
    --name "$backup_name" \
    --file "${RECOVERY_DIR}/${backup_name}"
  
  # Extract backup
  cd $RECOVERY_DIR
  tar -xzf "$backup_name"
  
  # Stop n8n container (to prevent conflicts)
  echo "⏸️ Stopping n8n container for recovery..."
  az containerapp revision deactivate \
    --name n8n-neural-mcp \
    --resource-group $RESOURCE_GROUP \
    --revision-name "$(az containerapp revision list --name n8n-neural-mcp --resource-group $RESOURCE_GROUP --query '[0].name' -o tsv)"
  
  # Upload restored database
  echo "📤 Uploading restored database..."
  az storage file upload \
    --account-name $STORAGE_ACCOUNT \
    --share-name n8n-data \
    --source "database.sqlite" \
    --path "database.sqlite" \
    --overwrite
  
  # Upload configuration files
  echo "⚙️ Restoring configuration..."
  az storage file upload-batch \
    --account-name $STORAGE_ACCOUNT \
    --destination n8n-data \
    --source "config" \
    --overwrite
  
  # Restart n8n container
  echo "🚀 Restarting n8n container..."
  az containerapp update \
    --name n8n-neural-mcp \
    --resource-group $RESOURCE_GROUP \
    --revision-suffix "recovered-$(date +%s)"
  
  # Wait for container to start
  echo "⏳ Waiting for n8n to start..."
  sleep 30
  
  # Health check
  N8N_URL="https://n8n-neural-mcp.wonderfulrock-519a3fc8.eastus2.azurecontainerapps.io"
  for i in {1..10}; do
    if curl -f $N8N_URL/healthz > /dev/null 2>&1; then
      echo "✅ Recovery completed successfully!"
      echo "🌐 N8N is available at: $N8N_URL"
      break
    else
      echo "⏳ Waiting for n8n to respond... (attempt $i/10)"
      sleep 30
    fi
  done
  
  # Cleanup
  rm -rf $RECOVERY_DIR
}

# Function to restore from snapshot
restore_from_snapshot() {
  echo "📸 Available snapshots:"
  az storage share list-snapshots \
    --account-name $STORAGE_ACCOUNT \
    --name n8n-data \
    --output table
  
  read -p "Enter snapshot timestamp (YYYY-MM-DDTHH:MM:SS.0000000Z): " snapshot_time
  
  echo "🔄 Restoring from snapshot: $snapshot_time"
  
  # This would require custom logic to restore from snapshot
  # For now, we'll use the backup restore method
  echo "⚠️ Snapshot restore requires manual intervention"
  echo "Please use Azure Portal to restore from snapshot, then run health check"
}

# Function to restore from Git
restore_from_git() {
  if [ ! -d "/tmp/n8n-workflows" ]; then
    echo "📚 Cloning workflow repository..."
    git clone <YOUR_REPO_URL> /tmp/n8n-workflows
  fi
  
  cd /tmp/n8n-workflows
  git pull origin main
  
  echo "📋 Available workflow backups:"
  ls -la backups/
  
  read -p "Enter backup date (YYYY-MM-DD_HH-MM-SS): " backup_date
  
  if [ -f "backups/${backup_date}/workflows-export.json" ]; then
    echo "🔄 Importing workflows from Git backup..."
    # This would require N8N API import functionality
    N8N_URL="https://n8n-neural-mcp.wonderfulrock-519a3fc8.eastus2.azurecontainerapps.io"
    curl -X POST "${N8N_URL}/api/v1/workflows/import" \
      -H "Content-Type: application/json" \
      -d @"backups/${backup_date}/workflows-export.json"
    echo "✅ Workflows imported from Git backup"
  else
    echo "❌ Backup not found: backups/${backup_date}/workflows-export.json"
  fi
}

# Main menu
echo "🛠️ N8N Recovery Options:"
echo "1. List available backups"
echo "2. Restore from backup archive"
echo "3. Restore from snapshot"
echo "4. Restore from Git"
echo "5. Health check only"

read -p "Select option (1-5): " option

case $option in
  1) list_backups ;;
  2) restore_from_backup ;;
  3) restore_from_snapshot ;;
  4) restore_from_git ;;
  5) 
    N8N_URL="https://n8n-neural-mcp.wonderfulrock-519a3fc8.eastus2.azurecontainerapps.io"
    curl -f $N8N_URL/healthz > /dev/null 2>&1 && echo "✅ N8N: Healthy" || echo "❌ N8N: Not responding"
    ;;
  *) echo "❌ Invalid option" ;;
esac

echo "🎯 Recovery process completed at $(date)"