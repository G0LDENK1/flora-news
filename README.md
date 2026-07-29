# 🌿 Flora News

> An AI-powered newsletter platform that discovers, summarizes, and publishes content automatically.

[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue.svg)](docker-compose.yml)
[![n8n](https://img.shields.io/badge/Workflows-n8n-orange.svg)](docker/n8n/workflows)

---

## What It Does

Flora News is a self-hosted newsletter automation platform. Every day, it:

1. 📡 **Collects** hundreds of articles from RSS feeds
2. 🔍 **Extracts** full article content
3. 🧹 **Deduplicates** to avoid repeats
4. 🤖 **Summarizes** each article with AI
5. 🗂️ **Categorizes** content automatically
6. 📊 **Ranks** stories by relevance and impact
7. ✍️ **Builds** a polished newsletter
8. 📧 **Publishes** to Beehiiv
9. 🌐 **Publishes** to Ghost (your website)
10. 📱 **Posts** to LinkedIn, X, and Threads
11. 📈 **Tracks** analytics

---

## Architecture

```
Internet
    │
    ▼
 Traefik (HTTPS, routing)
    │
    ├── n8n (12 automated workflows)
    ├── Flora Admin (dashboard)
    ├── Ghost (website)
    ├── Grafana (monitoring)
    └── MinIO (file storage)
         │
    ┌────┴────┐
PostgreSQL   Redis
    │
  Qdrant (vector search)
```

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/yourname/flora-news
cd flora-news

# 2. Configure
cp .env.example .env
nano .env  # Fill in your domain, API keys, etc.

# 3. Run setup
chmod +x scripts/setup.sh
./scripts/setup.sh

# 4. Seed example RSS feeds
docker-compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -f /sql/seed-feeds.sql

# 5. Import n8n workflows
./scripts/import-workflows.sh

# 6. Open your admin dashboard
open https://admin.yourdomain.com
```

---

## Services & URLs

| Service | URL | Purpose |
|---------|-----|---------|
| Admin Dashboard | `admin.yourdomain.com` | Control everything |
| n8n | `n8n.yourdomain.com` | Edit workflows |
| Ghost | `yourdomain.com` | Your website |
| Grafana | `grafana.yourdomain.com` | Monitoring |
| MinIO | `minio-console.yourdomain.com` | File storage |
| Traefik | `traefik.yourdomain.com` | Proxy dashboard |

---

## Repository Structure

```
flora-news/
├── docker/
│   ├── n8n/
│   │   └── workflows/          # 12 n8n workflow JSON files
│   ├── postgres/
│   │   └── init.sql            # DB initialization
│   ├── traefik/
│   │   ├── traefik.yml         # Static config
│   │   └── dynamic.yml         # Middleware config
│   ├── prometheus/
│   │   └── prometheus.yml      # Metrics config
│   └── grafana/
│       └── provisioning/       # Datasources + dashboards
├── admin/                      # Custom dashboard (Node.js + Express)
│   ├── src/server.js
│   ├── public/index.html
│   └── Dockerfile
├── sql/
│   └── schema.sql              # Full database schema
├── prompts/                    # AI prompt library
│   ├── summarize.md
│   ├── categorize.md
│   ├── rank.md
│   ├── newsletter.md
│   ├── linkedin.md
│   ├── tweet.md
│   ├── threads.md
│   └── seo.md
├── scripts/
│   ├── setup.sh                # First-time setup
│   ├── import-workflows.sh     # Import n8n workflows
│   ├── backup.sh               # Daily backup
│   └── seed-feeds.sql          # Example RSS feeds
├── docs/                       # Documentation
├── branding/                   # Logos, assets
├── .env.example                # Configuration template
├── docker-compose.yml          # Full stack definition
└── README.md
```

---

## Workflows

| # | Workflow | Schedule | Purpose |
|---|---------|----------|---------|
| 001 | Feed Collector | Every 2h | Fetch RSS feeds, upsert articles |
| 002 | HTML Extractor | Every 15m | Fetch full article content |
| 003 | Duplicate Checker | Every 20m | Hash + deduplicate articles |
| 004 | AI Summarizer | Every 15m | GPT-4o-mini summary + key points |
| 005 | AI Categorizer | Every 20m | Auto-assign category |
| 006 | Story Ranker | Every 1h | Score articles by relevance/impact |
| 007 | Newsletter Builder | 6AM daily | Build issue with GPT-4o |
| 008 | HTML Formatter | Every 30m | Render full HTML email |
| 009 | Beehiiv Publisher | 8AM daily | Send to Beehiiv |
| 010 | Social Publisher | Every 30m | Post to LinkedIn/X/Threads |
| 011 | Analytics Sync | Every 6h | Pull Beehiiv stats |
| 012 | Error Handler | On error | Log + alert on failures |

---

## Database Schema

Key tables:

- **sources** — News sources
- **feeds** — RSS/Atom feed URLs
- **articles** — All discovered content (with full pipeline status)
- **summaries** — Versioned AI summaries
- **categories** — Content categories
- **newsletter_issues** — Published issues
- **newsletter_sections** — Issue sections
- **social_posts** — Platform posts
- **sponsors** — Sponsorship campaigns
- **analytics** — Engagement tracking
- **workflow_logs** — Pipeline observability
- **knowledge_base** — Qdrant vector metadata

---

## AI Prompts

Prompts live in `prompts/` as Markdown files with `{{placeholders}}`. Edit them to change how AI processes content — no workflow edits needed.

---

## Environment Variables

See `.env.example` for all configuration options. Key ones:

```bash
DOMAIN=flora.example.com           # Your domain
OPENAI_API_KEY=sk-...              # OpenAI API key
BEEHIIV_API_KEY=...                # Beehiiv API key
BEEHIIV_PUBLICATION_ID=pub_...     # Your publication ID
POSTGRES_PASSWORD=...              # Set a strong password
N8N_ENCRYPTION_KEY=...             # 32-char random key
```

---

## Adding RSS Feeds

**Via Admin Dashboard:** Feeds → Add Feed → paste URL

**Via SQL:**
```sql
INSERT INTO sources (name, url, domain) VALUES ('My Blog', 'https://myblog.com', 'myblog.com');
INSERT INTO feeds (source_id, url) VALUES ('<source_id>', 'https://myblog.com/feed.xml');
```

---

## Backups

```bash
# Add to cron
0 3 * * * /path/to/flora-news/scripts/backup.sh
```

Backs up PostgreSQL, n8n workflows, and MinIO to `/var/backups/flora-news/`. Keeps 7 days.

---

## Monitoring

- **Grafana** → Dashboards for article pipeline, newsletter metrics, system health
- **Prometheus** → Metrics from Traefik, n8n, Postgres, Redis
- **Workflow Logs** → Available in Admin Dashboard → Workflow Logs

---

## License

MIT — Build your own newsletter empire.

---

*Built with n8n, PostgreSQL, Redis, Qdrant, MinIO, Ghost, Traefik, Grafana, and OpenAI.*
