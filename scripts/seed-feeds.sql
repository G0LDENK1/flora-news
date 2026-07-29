-- Seed RSS feeds to get started
-- Run: docker-compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -f /sql/seed-feeds.sql

-- Sources
INSERT INTO sources (name, url, domain, category, reliability) VALUES
  ('TechCrunch', 'https://techcrunch.com', 'techcrunch.com', 'tech', 0.85),
  ('Wired', 'https://wired.com', 'wired.com', 'tech', 0.90),
  ('The Verge', 'https://theverge.com', 'theverge.com', 'tech', 0.85),
  ('Hacker News', 'https://news.ycombinator.com', 'news.ycombinator.com', 'tech', 0.80),
  ('MIT Technology Review', 'https://technologyreview.com', 'technologyreview.com', 'ai', 0.95),
  ('VentureBeat', 'https://venturebeat.com', 'venturebeat.com', 'ai', 0.80),
  ('ArXiv AI', 'https://arxiv.org', 'arxiv.org', 'ai', 0.95),
  ('Ars Technica', 'https://arstechnica.com', 'arstechnica.com', 'tech', 0.90),
  ('TechMeme', 'https://techmeme.com', 'techmeme.com', 'tech', 0.85),
  ('Product Hunt', 'https://producthunt.com', 'producthunt.com', 'startups', 0.75),
  ('Crunchbase News', 'https://news.crunchbase.com', 'news.crunchbase.com', 'startups', 0.85),
  ('GitHub Blog', 'https://github.blog', 'github.blog', 'open-source', 0.95),
  ('Krebs on Security', 'https://krebsonsecurity.com', 'krebsonsecurity.com', 'security', 0.95),
  ('Schneier on Security', 'https://schneier.com', 'schneier.com', 'security', 0.95)
ON CONFLICT (url) DO NOTHING;

-- Feeds
INSERT INTO feeds (source_id, url, title)
SELECT s.id, f.url, f.title FROM (VALUES
  ('https://techcrunch.com', 'https://feeds.feedburner.com/TechCrunch', 'TechCrunch'),
  ('https://wired.com', 'https://www.wired.com/feed/rss', 'Wired'),
  ('https://theverge.com', 'https://www.theverge.com/rss/index.xml', 'The Verge'),
  ('https://news.ycombinator.com', 'https://news.ycombinator.com/rss', 'Hacker News'),
  ('https://technologyreview.com', 'https://www.technologyreview.com/feed/', 'MIT Tech Review'),
  ('https://venturebeat.com', 'https://venturebeat.com/feed/', 'VentureBeat'),
  ('https://arstechnica.com', 'https://feeds.arstechnica.com/arstechnica/index', 'Ars Technica'),
  ('https://github.blog', 'https://github.blog/feed/', 'GitHub Blog'),
  ('https://krebsonsecurity.com', 'https://krebsonsecurity.com/feed/', 'Krebs on Security'),
  ('https://news.crunchbase.com', 'https://news.crunchbase.com/feed/', 'Crunchbase News')
) AS f(source_url, url, title)
JOIN sources s ON s.url = f.source_url
ON CONFLICT (url) DO NOTHING;
