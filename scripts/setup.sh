#!/bin/bash
# =============================================================================
# flora-news — First-time setup script
# Run this once on your VPS after cloning the repo
# =============================================================================
set -e

echo "🌿 Flora News Setup"
echo "==================="

# Check dependencies
for cmd in docker docker-compose git openssl; do
  if ! command -v $cmd &> /dev/null; then
    echo "❌ $cmd is required but not installed"
    exit 1
  fi
done

echo "✅ Dependencies found"

# Copy env file
if [ ! -f .env ]; then
  cp .env.example .env
  echo "📝 Created .env from .env.example — please edit it now!"
  echo ""
  echo "Required fields:"
  echo "  - DOMAIN"
  echo "  - ACME_EMAIL"
  echo "  - POSTGRES_PASSWORD"
  echo "  - OPENAI_API_KEY"
  echo "  - BEEHIIV_API_KEY + BEEHIIV_PUBLICATION_ID"
  echo ""
  read -p "Press Enter when you've configured .env..."
fi

# Load env
source .env

# Generate secrets if not set
if grep -q "change_me_strong_password" .env; then
  PG_PASS=$(openssl rand -hex 16)
  REDIS_PASS=$(openssl rand -hex 16)
  N8N_KEY=$(openssl rand -hex 16)
  ADMIN_SECRET=$(openssl rand -hex 16)
  QDRANT_KEY=$(openssl rand -hex 16)

  sed -i "s/change_me_strong_password/${PG_PASS}/g" .env
  sed -i "s/change_me_redis_password/${REDIS_PASS}/g" .env
  sed -i "s/change_me_32char_encryption_key_here/${N8N_KEY}/g" .env
  sed -i "s/change_me_admin_dashboard_secret/${ADMIN_SECRET}/g" .env
  sed -i "s/change_me_qdrant_api_key/${QDRANT_KEY}/g" .env
  echo "🔐 Generated secure random passwords"
fi

# Create Traefik password file (basic auth for traefik dashboard)
if command -v htpasswd &> /dev/null; then
  echo ""
  read -p "Traefik dashboard username: " TRAEFIK_USER
  htpasswd -c docker/traefik/.htpasswd "$TRAEFIK_USER"
else
  echo "⚠️  htpasswd not found — skipping Traefik auth setup (install apache2-utils)"
fi

# Create Ghost MySQL data directory
mkdir -p docker/ghost/ghost-db

# Create Grafana provisioning dirs
mkdir -p docker/grafana/provisioning/{datasources,dashboards}

# Pull images
echo ""
echo "🐳 Pulling Docker images..."
docker-compose pull

# Build custom images
echo "🔨 Building custom images..."
docker-compose build flora-admin

# Start infrastructure
echo "🚀 Starting infrastructure..."
docker-compose up -d postgres redis

echo "⏳ Waiting for Postgres to be ready..."
sleep 10

# Run migrations
echo "🗄️  Running database migrations..."
docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /sql/schema.sql || true

# Start remaining services
docker-compose up -d

echo ""
echo "✅ Flora News is starting up!"
echo ""
echo "Services:"
echo "  📊 Admin:     https://admin.${DOMAIN}"
echo "  🔧 n8n:       https://n8n.${DOMAIN}"
echo "  🌐 Ghost:     https://${DOMAIN}"
echo "  📈 Grafana:   https://grafana.${DOMAIN}"
echo "  💾 MinIO:     https://minio-console.${DOMAIN}"
echo ""
echo "Next steps:"
echo "  1. Open n8n and import workflows from docker/n8n/workflows/"
echo "  2. Add your RSS feeds via the admin dashboard"
echo "  3. Configure your Beehiiv publication"
echo "  4. Set up Ghost theme"
echo ""
echo "🌿 Good luck with Flora News!"
