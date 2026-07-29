require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { Pool } = require('pg');
const { createClient } = require('redis');
const client = require('prom-client');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3001;

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------
const db = new Pool({
  host: process.env.POSTGRES_HOST || 'postgres',
  port: parseInt(process.env.POSTGRES_PORT || '5432'),
  database: process.env.POSTGRES_DB || 'flora',
  user: process.env.POSTGRES_USER || 'flora',
  password: process.env.POSTGRES_PASSWORD,
  max: 10,
  idleTimeoutMillis: 30000,
});

// ---------------------------------------------------------------------------
// Redis
// ---------------------------------------------------------------------------
const redis = createClient({
  socket: { host: process.env.REDIS_HOST || 'redis', port: parseInt(process.env.REDIS_PORT || '6379') },
  password: process.env.REDIS_PASSWORD,
});
redis.connect().catch(console.error);

// ---------------------------------------------------------------------------
// Prometheus
// ---------------------------------------------------------------------------
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'flora_admin_http_duration_seconds',
  help: 'HTTP request duration',
  labelNames: ['method', 'route', 'status'],
  registers: [register],
});

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../public')));

const limiter = rateLimit({ windowMs: 60000, max: 200 });
app.use('/api', limiter);

// Auth middleware
const AUTH_SECRET = process.env.ADMIN_SECRET || 'changeme';
function requireAuth(req, res, next) {
  const token = req.headers['x-admin-token'] || req.query.token;
  if (token !== AUTH_SECRET) return res.status(401).json({ error: 'Unauthorized' });
  next();
}

// ---------------------------------------------------------------------------
// Metrics endpoint
// ---------------------------------------------------------------------------
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------
app.get('/health', async (req, res) => {
  try {
    await db.query('SELECT 1');
    res.json({ status: 'ok', db: 'connected', time: new Date().toISOString() });
  } catch (e) {
    res.status(500).json({ status: 'error', db: 'disconnected' });
  }
});

// ---------------------------------------------------------------------------
// API Routes
// ---------------------------------------------------------------------------

// Dashboard Stats
app.get('/api/stats', requireAuth, async (req, res) => {
  try {
    const [stats, issues, errors] = await Promise.all([
      db.query('SELECT * FROM v_dashboard_stats'),
      db.query(`SELECT id, issue_number, subject_line, status, open_rate, click_rate, recipients, sent_at 
                FROM newsletter_issues ORDER BY created_at DESC LIMIT 5`),
      db.query(`SELECT workflow_name, error_msg, started_at FROM workflow_logs 
                WHERE status = 'error' ORDER BY started_at DESC LIMIT 10`),
    ]);
    res.json({
      stats: stats.rows[0],
      recent_issues: issues.rows,
      recent_errors: errors.rows,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Today's Articles
app.get('/api/articles/today', requireAuth, async (req, res) => {
  try {
    const { rows } = await db.query(`
      SELECT * FROM v_today_articles LIMIT 100
    `);
    res.json(rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Articles with filters
app.get('/api/articles', requireAuth, async (req, res) => {
  const { status, category, limit = 50, offset = 0, q } = req.query;
  try {
    let query = `
      SELECT a.id, a.url, a.title, a.author, a.published_at, a.summary, 
             a.final_score, a.status, a.sentiment, a.word_count,
             c.name as category, c.icon as category_icon, s.name as source_name
      FROM articles a
      LEFT JOIN categories c ON c.id = a.category_id
      LEFT JOIN sources s ON s.id = a.source_id
      WHERE 1=1
    `;
    const params = [];
    if (status) { params.push(status); query += ` AND a.status = $${params.length}`; }
    if (category) { params.push(category); query += ` AND c.slug = $${params.length}`; }
    if (q) { params.push(`%${q}%`); query += ` AND (a.title ILIKE $${params.length} OR a.summary ILIKE $${params.length})`; }
    params.push(limit); query += ` ORDER BY a.created_at DESC LIMIT $${params.length}`;
    params.push(offset); query += ` OFFSET $${params.length}`;

    const { rows } = await db.query(query, params);
    res.json(rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Article approve/reject
app.patch('/api/articles/:id/status', requireAuth, async (req, res) => {
  const { status } = req.body;
  const validStatuses = ['approved', 'rejected', 'published'];
  if (!validStatuses.includes(status)) return res.status(400).json({ error: 'Invalid status' });
  try {
    await db.query('UPDATE articles SET status = $1, updated_at = NOW() WHERE id = $2', [status, req.params.id]);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Newsletter issues
app.get('/api/issues', requireAuth, async (req, res) => {
  try {
    const { rows } = await db.query(`
      SELECT id, issue_number, title, subject_line, preview_text, status,
             scheduled_for, sent_at, recipients, opens, clicks, open_rate, click_rate,
             beehiiv_url, ghost_url, created_at
      FROM newsletter_issues ORDER BY created_at DESC LIMIT 20
    `);
    res.json(rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Issue detail
app.get('/api/issues/:id', requireAuth, async (req, res) => {
  try {
    const [issue, articles] = await Promise.all([
      db.query('SELECT * FROM newsletter_issues WHERE id = $1', [req.params.id]),
      db.query(`
        SELECT a.id, a.title, a.url, a.summary, a.final_score, nsa.sort_order, nsa.blurb
        FROM newsletter_section_articles nsa
        JOIN newsletter_sections ns ON ns.id = nsa.section_id
        JOIN articles a ON a.id = nsa.article_id
        WHERE ns.issue_id = $1
        ORDER BY ns.sort_order, nsa.sort_order
      `, [req.params.id]),
    ]);
    if (!issue.rows[0]) return res.status(404).json({ error: 'Not found' });
    res.json({ ...issue.rows[0], articles: articles.rows });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Schedule issue
app.patch('/api/issues/:id/schedule', requireAuth, async (req, res) => {
  const { scheduled_for } = req.body;
  try {
    await db.query('UPDATE newsletter_issues SET status = $1, scheduled_for = $2, updated_at = NOW() WHERE id = $3',
      ['scheduled', scheduled_for, req.params.id]);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Social posts
app.get('/api/social', requireAuth, async (req, res) => {
  try {
    const { rows } = await db.query(`
      SELECT sp.*, a.title as article_title
      FROM social_posts sp LEFT JOIN articles a ON a.id = sp.article_id
      ORDER BY sp.created_at DESC LIMIT 50
    `);
    res.json(rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Feeds management
app.get('/api/feeds', requireAuth, async (req, res) => {
  try {
    const { rows } = await db.query(`
      SELECT f.*, s.name as source_name, s.domain
      FROM feeds f LEFT JOIN sources s ON s.id = f.source_id
      ORDER BY f.active DESC, f.last_fetched DESC NULLS LAST
    `);
    res.json(rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Add feed
app.post('/api/feeds', requireAuth, async (req, res) => {
  const { url, source_name } = req.body;
  if (!url) return res.status(400).json({ error: 'URL required' });
  try {
    const domain = new URL(url).hostname;
    const src = await db.query(
      `INSERT INTO sources (name, url, domain) VALUES ($1, $2, $3)
       ON CONFLICT (url) DO UPDATE SET name = EXCLUDED.name RETURNING id`,
      [source_name || domain, url, domain]
    );
    const feed = await db.query(
      'INSERT INTO feeds (source_id, url) VALUES ($1, $2) ON CONFLICT (url) DO NOTHING RETURNING id',
      [src.rows[0].id, url]
    );
    res.json({ success: true, feed_id: feed.rows[0]?.id });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Sponsors
app.get('/api/sponsors', requireAuth, async (req, res) => {
  try {
    const { rows } = await db.query('SELECT * FROM sponsors ORDER BY active DESC, created_at DESC');
    res.json(rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Workflow logs
app.get('/api/logs', requireAuth, async (req, res) => {
  try {
    const { rows } = await db.query(`
      SELECT * FROM workflow_logs ORDER BY started_at DESC LIMIT 100
    `);
    res.json(rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Error webhook (called by n8n error handler)
app.post('/api/webhook/error', async (req, res) => {
  console.error('[ERROR WEBHOOK]', req.body);
  res.json({ received: true });
});

// Analytics summary
app.get('/api/analytics', requireAuth, async (req, res) => {
  try {
    const { rows } = await db.query(`
      SELECT
        DATE_TRUNC('day', ni.sent_at) as date,
        COUNT(*) as issues_sent,
        AVG(ni.open_rate) as avg_open_rate,
        AVG(ni.click_rate) as avg_click_rate,
        SUM(ni.recipients) as total_recipients
      FROM newsletter_issues ni
      WHERE ni.status = 'sent' AND ni.sent_at >= NOW() - INTERVAL '30 days'
      GROUP BY DATE_TRUNC('day', ni.sent_at)
      ORDER BY date DESC
    `);
    res.json(rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Categories
app.get('/api/categories', requireAuth, async (req, res) => {
  try {
    const { rows } = await db.query(`
      SELECT c.*, COUNT(a.id) as article_count
      FROM categories c LEFT JOIN articles a ON a.category_id = c.id
      GROUP BY c.id ORDER BY c.sort_order, c.name
    `);
    res.json(rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// SPA fallback
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
app.listen(PORT, () => {
  console.log(`🌿 Flora Admin running on :${PORT}`);
});
