# Deployment Guide

## Prerequisites

- VPS with **4GB+ RAM** (8GB recommended), **2+ CPU cores**
- Ubuntu 22.04 LTS (recommended)
- Docker + Docker Compose installed
- A domain with DNS pointing to your VPS IP
- Ports 80 and 443 open in your firewall

## VPS Setup (fresh Ubuntu)

```bash
# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker $USER

# Install Docker Compose
apt install docker-compose-plugin -y

# Install utilities
apt install git htpasswd jq -y

# Verify
docker --version
docker compose version
```

## DNS Records

Create these DNS A records pointing to your VPS IP:

```
yourdomain.com          → YOUR_VPS_IP
n8n.yourdomain.com      → YOUR_VPS_IP
admin.yourdomain.com    → YOUR_VPS_IP
grafana.yourdomain.com  → YOUR_VPS_IP
minio.yourdomain.com    → YOUR_VPS_IP
minio-console.yourdomain.com → YOUR_VPS_IP
traefik.yourdomain.com  → YOUR_VPS_IP
```

## First Deploy

```bash
git clone https://github.com/yourname/flora-news
cd flora-news
./scripts/setup.sh
```

## Updating

```bash
git pull
docker-compose pull
docker-compose up -d
```

## Ghost Setup

After deploying, visit `https://yourdomain.com/ghost` to complete Ghost setup:
1. Create your admin account
2. Configure your site title and description
3. Install a theme (Casper is default)
4. Get your Ghost Admin API key for n8n integration

## n8n Credentials Setup

In n8n, configure these credentials:
- **OpenAI**: API key
- **PostgreSQL**: Use internal hostname `postgres:5432`
- **HTTP Header Auth (Beehiiv)**: Bearer token
- **LinkedIn OAuth2**
- **Twitter/X OAuth1**
- **HTTP Header Auth (Threads)**

## Beehiiv Setup

1. Create a publication at beehiiv.com
2. Get your API key from Settings → API
3. Copy your Publication ID from Settings → General
4. Add both to `.env`

## Monitoring

- Grafana: `https://grafana.yourdomain.com`
- Login with GRAFANA_ADMIN_USER / GRAFANA_ADMIN_PASSWORD from .env
- Import the community Traefik and n8n dashboards from grafana.com

## Scaling

For higher volume, consider:
- Increasing n8n queue workers: `N8N_CLUSTER_MODE=true`
- Moving PostgreSQL to a managed service (PlanetScale, Supabase, Neon)
- Using Cloudflare as CDN in front of Ghost
- Redis Sentinel for HA cache
