-- =============================================================================
-- flora-news PostgreSQL Initialization
-- Creates all required databases and users
-- =============================================================================

-- Create n8n database
CREATE DATABASE n8n;
GRANT ALL PRIVILEGES ON DATABASE n8n TO flora;

-- Create extensions on flora db
\c flora;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- Create schema
\i /sql/schema.sql
