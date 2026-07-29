-- =============================================================================
-- flora-news — Full Database Schema
-- =============================================================================

-- ---------------------------------------------------------------------------
-- SOURCES — News sources / websites
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sources (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name          TEXT NOT NULL,
  url           TEXT NOT NULL UNIQUE,
  domain        TEXT NOT NULL,
  category      TEXT,
  language      TEXT DEFAULT 'en',
  country       TEXT DEFAULT 'US',
  reliability   NUMERIC(3,2) DEFAULT 0.80,  -- 0.0 to 1.0
  active        BOOLEAN DEFAULT TRUE,
  last_fetched  TIMESTAMPTZ,
  fetch_errors  INTEGER DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- FEEDS — RSS/Atom feed endpoints
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS feeds (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  source_id     UUID REFERENCES sources(id) ON DELETE CASCADE,
  url           TEXT NOT NULL UNIQUE,
  title         TEXT,
  feed_type     TEXT DEFAULT 'rss',  -- rss, atom, json
  active        BOOLEAN DEFAULT TRUE,
  last_fetched  TIMESTAMPTZ,
  last_etag     TEXT,
  last_modified TEXT,
  fetch_errors  INTEGER DEFAULT 0,
  item_count    INTEGER DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- CATEGORIES — Article categories
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS categories (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug        TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  description TEXT,
  color       TEXT DEFAULT '#6366f1',
  icon        TEXT DEFAULT '📰',
  active      BOOLEAN DEFAULT TRUE,
  sort_order  INTEGER DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO categories (slug, name, icon, color) VALUES
  ('ai', 'Artificial Intelligence', '🤖', '#7c3aed'),
  ('tech', 'Technology', '💻', '#2563eb'),
  ('business', 'Business', '💼', '#059669'),
  ('science', 'Science', '🔬', '#0891b2'),
  ('security', 'Security', '🔒', '#dc2626'),
  ('startups', 'Startups', '🚀', '#d97706'),
  ('design', 'Design', '🎨', '#db2777'),
  ('open-source', 'Open Source', '📦', '#65a30d'),
  ('world', 'World News', '🌍', '#4b5563'),
  ('other', 'Other', '📌', '#6b7280')
ON CONFLICT (slug) DO NOTHING;

-- ---------------------------------------------------------------------------
-- ARTICLES — Discovered articles
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS articles (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  feed_id         UUID REFERENCES feeds(id),
  source_id       UUID REFERENCES sources(id),
  
  -- Original content
  url             TEXT NOT NULL UNIQUE,
  title           TEXT NOT NULL,
  author          TEXT,
  published_at    TIMESTAMPTZ,
  raw_content     TEXT,
  raw_html        TEXT,
  word_count      INTEGER,
  reading_time    INTEGER,  -- minutes
  
  -- AI-processed
  category_id     UUID REFERENCES categories(id),
  summary         TEXT,
  key_points      JSONB DEFAULT '[]',
  entities        JSONB DEFAULT '[]',  -- people, orgs, places
  topics          TEXT[],
  sentiment       TEXT DEFAULT 'neutral',  -- positive, negative, neutral
  
  -- Scoring
  relevance_score NUMERIC(4,3) DEFAULT 0,   -- 0.0 to 1.0
  quality_score   NUMERIC(4,3) DEFAULT 0,   -- 0.0 to 1.0
  novelty_score   NUMERIC(4,3) DEFAULT 0,   -- 0.0 to 1.0
  final_score     NUMERIC(4,3) DEFAULT 0,   -- weighted composite
  
  -- Status
  status          TEXT DEFAULT 'new',
  -- new → extracted → summarized → scored → approved/rejected/published
  
  -- Deduplication
  content_hash    TEXT,
  duplicate_of    UUID REFERENCES articles(id),
  
  -- Images
  image_url       TEXT,
  image_stored    TEXT,  -- MinIO path
  
  -- Metadata
  language        TEXT DEFAULT 'en',
  is_paywalled    BOOLEAN DEFAULT FALSE,
  
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  
  CONSTRAINT valid_status CHECK (status IN (
    'new', 'extracting', 'extracted', 'summarizing', 'summarized',
    'scoring', 'scored', 'approved', 'rejected', 'published', 'error'
  ))
);

CREATE INDEX idx_articles_status ON articles(status);
CREATE INDEX idx_articles_published_at ON articles(published_at DESC);
CREATE INDEX idx_articles_final_score ON articles(final_score DESC);
CREATE INDEX idx_articles_category ON articles(category_id);
CREATE INDEX idx_articles_created_at ON articles(created_at DESC);
CREATE INDEX idx_articles_content_hash ON articles(content_hash) WHERE content_hash IS NOT NULL;

-- Full text search
ALTER TABLE articles ADD COLUMN IF NOT EXISTS tsv TSVECTOR;
CREATE INDEX idx_articles_tsv ON articles USING GIN(tsv);

CREATE OR REPLACE FUNCTION articles_tsv_trigger() RETURNS TRIGGER AS $$
BEGIN
  NEW.tsv = to_tsvector('english',
    coalesce(NEW.title, '') || ' ' ||
    coalesce(NEW.summary, '') || ' ' ||
    coalesce(array_to_string(NEW.topics, ' '), '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER articles_tsv_update
  BEFORE INSERT OR UPDATE ON articles
  FOR EACH ROW EXECUTE FUNCTION articles_tsv_trigger();

-- ---------------------------------------------------------------------------
-- SUMMARIES — AI-generated summaries (versioned)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS summaries (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  article_id  UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  version     INTEGER DEFAULT 1,
  model       TEXT NOT NULL,
  prompt_hash TEXT,
  summary     TEXT NOT NULL,
  key_points  JSONB DEFAULT '[]',
  tokens_used INTEGER,
  cost_usd    NUMERIC(10,6),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_summaries_article ON summaries(article_id);

-- ---------------------------------------------------------------------------
-- NEWSLETTER ISSUES
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS newsletter_issues (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  issue_number    SERIAL,
  title           TEXT,
  subject_line    TEXT,
  preview_text    TEXT,
  status          TEXT DEFAULT 'draft',
  -- draft → building → review → scheduled → sending → sent
  
  scheduled_for   TIMESTAMPTZ,
  sent_at         TIMESTAMPTZ,
  
  -- Content
  intro_html      TEXT,
  outro_html      TEXT,
  sponsor_html    TEXT,
  full_html       TEXT,
  full_text       TEXT,
  
  -- Beehiiv
  beehiiv_post_id TEXT,
  beehiiv_url     TEXT,
  
  -- Ghost
  ghost_post_id   TEXT,
  ghost_url       TEXT,
  
  -- Analytics
  recipients      INTEGER DEFAULT 0,
  opens           INTEGER DEFAULT 0,
  clicks          INTEGER DEFAULT 0,
  unsubscribes    INTEGER DEFAULT 0,
  open_rate       NUMERIC(5,2),
  click_rate      NUMERIC(5,2),
  
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT valid_issue_status CHECK (status IN (
    'draft', 'building', 'review', 'scheduled', 'sending', 'sent', 'cancelled'
  ))
);

-- ---------------------------------------------------------------------------
-- NEWSLETTER SECTIONS — Sections within an issue
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS newsletter_sections (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  issue_id     UUID NOT NULL REFERENCES newsletter_issues(id) ON DELETE CASCADE,
  category_id  UUID REFERENCES categories(id),
  section_type TEXT DEFAULT 'articles',
  -- articles, sponsor, ad, callout, divider, custom
  title        TEXT,
  body_html    TEXT,
  sort_order   INTEGER DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- NEWSLETTER SECTION ARTICLES — M2M: sections ↔ articles
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS newsletter_section_articles (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  section_id  UUID NOT NULL REFERENCES newsletter_sections(id) ON DELETE CASCADE,
  article_id  UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  sort_order  INTEGER DEFAULT 0,
  blurb       TEXT,  -- custom teaser override
  UNIQUE(section_id, article_id)
);

-- ---------------------------------------------------------------------------
-- SOCIAL POSTS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS social_posts (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  issue_id    UUID REFERENCES newsletter_issues(id),
  article_id  UUID REFERENCES articles(id),
  platform    TEXT NOT NULL,  -- linkedin, x, threads
  content     TEXT NOT NULL,
  media_url   TEXT,
  status      TEXT DEFAULT 'draft',
  -- draft → scheduled → posted → failed
  scheduled_for TIMESTAMPTZ,
  posted_at   TIMESTAMPTZ,
  platform_id TEXT,  -- ID returned by the platform
  platform_url TEXT,
  error_msg   TEXT,
  
  -- Analytics
  impressions INTEGER DEFAULT 0,
  likes       INTEGER DEFAULT 0,
  shares      INTEGER DEFAULT 0,
  comments    INTEGER DEFAULT 0,
  clicks      INTEGER DEFAULT 0,
  
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT valid_platform CHECK (platform IN ('linkedin', 'x', 'threads')),
  CONSTRAINT valid_post_status CHECK (status IN ('draft', 'scheduled', 'posted', 'failed', 'cancelled'))
);

-- ---------------------------------------------------------------------------
-- SPONSORS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sponsors (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name          TEXT NOT NULL,
  company       TEXT,
  email         TEXT,
  website       TEXT,
  logo_url      TEXT,
  
  -- Campaign
  campaign_name TEXT,
  ad_copy       TEXT,
  cta_text      TEXT DEFAULT 'Learn More',
  cta_url       TEXT,
  
  -- Placement
  placement     TEXT DEFAULT 'top',  -- top, middle, bottom
  issues_booked INTEGER DEFAULT 1,
  issues_used   INTEGER DEFAULT 0,
  
  -- Financials
  rate_per_issue NUMERIC(10,2),
  total_paid    NUMERIC(10,2) DEFAULT 0,
  
  active        BOOLEAN DEFAULT TRUE,
  start_date    DATE,
  end_date      DATE,
  
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- AFFILIATE LINKS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS affiliate_links (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name         TEXT NOT NULL,
  original_url TEXT NOT NULL,
  tracking_url TEXT NOT NULL,
  program      TEXT,
  commission   NUMERIC(5,2),
  clicks       INTEGER DEFAULT 0,
  conversions  INTEGER DEFAULT 0,
  revenue      NUMERIC(10,2) DEFAULT 0,
  active       BOOLEAN DEFAULT TRUE,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- ANALYTICS — Issue-level tracking
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS analytics (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  issue_id    UUID REFERENCES newsletter_issues(id),
  article_id  UUID REFERENCES articles(id),
  event_type  TEXT NOT NULL,
  -- open, click, subscribe, unsubscribe, share, bounce
  platform    TEXT,
  subscriber_hash TEXT,  -- anonymized subscriber ID
  link_url    TEXT,
  user_agent  TEXT,
  country     TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_analytics_issue ON analytics(issue_id);
CREATE INDEX idx_analytics_event ON analytics(event_type);
CREATE INDEX idx_analytics_created ON analytics(created_at DESC);

-- ---------------------------------------------------------------------------
-- USERS — Admin users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email         TEXT NOT NULL UNIQUE,
  name          TEXT,
  role          TEXT DEFAULT 'editor',
  -- admin, editor, viewer
  password_hash TEXT,
  api_key       TEXT UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
  active        BOOLEAN DEFAULT TRUE,
  last_login    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- WORKFLOW LOGS — Track n8n workflow runs
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workflow_logs (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workflow_name TEXT NOT NULL,
  run_id        TEXT,
  status        TEXT,  -- running, success, error
  items_in      INTEGER DEFAULT 0,
  items_out     INTEGER DEFAULT 0,
  error_msg     TEXT,
  duration_ms   INTEGER,
  started_at    TIMESTAMPTZ DEFAULT NOW(),
  finished_at   TIMESTAMPTZ
);

CREATE INDEX idx_workflow_logs_name ON workflow_logs(workflow_name);
CREATE INDEX idx_workflow_logs_status ON workflow_logs(status);
CREATE INDEX idx_workflow_logs_started ON workflow_logs(started_at DESC);

-- ---------------------------------------------------------------------------
-- KNOWLEDGE BASE — Vector search metadata (Qdrant handles vectors)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS knowledge_base (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  article_id  UUID REFERENCES articles(id),
  qdrant_id   TEXT UNIQUE,
  chunk_index INTEGER DEFAULT 0,
  chunk_text  TEXT NOT NULL,
  embedding_model TEXT DEFAULT 'text-embedding-3-small',
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_kb_article ON knowledge_base(article_id);

-- ---------------------------------------------------------------------------
-- FUNCTIONS & TRIGGERS — Auto-update updated_at
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['sources','feeds','articles','newsletter_issues','sponsors','social_posts','users'] LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION update_updated_at()',
      t
    );
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- VIEWS
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_today_articles AS
SELECT
  a.id, a.url, a.title, a.author, a.published_at,
  a.summary, a.final_score, a.status, a.sentiment,
  c.name AS category, c.icon AS category_icon,
  s.name AS source_name
FROM articles a
LEFT JOIN categories c ON c.id = a.category_id
LEFT JOIN sources s ON s.id = a.source_id
WHERE a.created_at >= NOW() - INTERVAL '24 hours'
ORDER BY a.final_score DESC;

CREATE OR REPLACE VIEW v_dashboard_stats AS
SELECT
  (SELECT COUNT(*) FROM articles WHERE created_at >= NOW() - INTERVAL '24 hours') AS articles_today,
  (SELECT COUNT(*) FROM articles WHERE status = 'new') AS queue_pending,
  (SELECT COUNT(*) FROM articles WHERE status = 'error') AS queue_errors,
  (SELECT COUNT(*) FROM newsletter_issues WHERE status = 'sent' AND sent_at >= NOW() - INTERVAL '30 days') AS issues_this_month,
  (SELECT AVG(open_rate) FROM newsletter_issues WHERE status = 'sent' AND sent_at >= NOW() - INTERVAL '30 days') AS avg_open_rate,
  (SELECT COUNT(*) FROM social_posts WHERE status = 'posted' AND posted_at >= NOW() - INTERVAL '24 hours') AS social_posts_today,
  (SELECT COUNT(*) FROM feeds WHERE active = TRUE) AS active_feeds,
  (SELECT COUNT(*) FROM sources WHERE active = TRUE) AS active_sources;
