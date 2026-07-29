#!/bin/bash
# Daily backup script — run via cron
# 0 3 * * * /path/to/flora-news/scripts/backup.sh

set -e
source "$(dirname "$0")/../.env"

BACKUP_DIR="/var/backups/flora-news"
DATE=$(date +%Y-%m-%d)
mkdir -p "$BACKUP_DIR"

echo "🗄️  Backing up PostgreSQL..."
docker-compose exec -T postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip > "$BACKUP_DIR/postgres-$DATE.sql.gz"

echo "📦 Backing up n8n data..."
docker run --rm -v flora-news_n8n_data:/data -v "$BACKUP_DIR":/backup alpine \
  tar czf "/backup/n8n-$DATE.tar.gz" /data

echo "📂 Backing up MinIO data..."
docker run --rm -v flora-news_minio_data:/data -v "$BACKUP_DIR":/backup alpine \
  tar czf "/backup/minio-$DATE.tar.gz" /data

# Keep 7 days of backups
find "$BACKUP_DIR" -name "*.gz" -mtime +7 -delete

echo "✅ Backup complete: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"
