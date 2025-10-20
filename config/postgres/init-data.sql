---
-- PostgreSQL Initialization Script for n8n
-- This script runs automatically when PostgreSQL container starts

-- ============================================================================
-- PERFORMANCE TUNING PARAMETERS
-- ============================================================================

-- Connection pooling
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET superuser_reserved_connections = 3;

-- Shared memory (effective for large queries)
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';

-- Work memory (per operation)
ALTER SYSTEM SET work_mem = '10MB';

-- Maintenance memory
ALTER SYSTEM SET maintenance_work_mem = '128MB';

-- Query planning
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET cpu_tuple_cost = 0.01;
ALTER SYSTEM SET cpu_index_tuple_cost = 0.005;

-- WAL (Write-Ahead Log) for reliability
ALTER SYSTEM SET wal_level = replica;
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET wal_keep_size = '1GB';
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;

-- Autovacuum tuning for high-throughput workflows
ALTER SYSTEM SET autovacuum = on;
ALTER SYSTEM SET autovacuum_naptime = '10s';
ALTER SYSTEM SET autovacuum_vacuum_threshold = 50;
ALTER SYSTEM SET autovacuum_analyze_threshold = 50;
ALTER SYSTEM SET autovacuum_vacuum_scale_factor = 0.01;
ALTER SYSTEM SET autovacuum_analyze_scale_factor = 0.005;

-- Logging for debugging
ALTER SYSTEM SET log_min_duration_statement = 5000; -- Log queries slower than 5 seconds
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;
ALTER SYSTEM SET log_statement = 'mod'; -- DDL + DML + CALL
ALTER SYSTEM SET log_duration = off;

-- pg_stat_statements configuration (Load Library only. Config parameters must be set
-- via environment variables or after a server restart/reload)
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
-- **Removed failing ALTER SYSTEM SET pg_stat_statements.track = 'all';**
-- **Removed failing ALTER SYSTEM SET pg_stat_statements.max = 10000;**

-- ============================================================================
-- USER AND DATABASE SETUP
-- ============================================================================

-- Create n8n user (non-root, standard privileges)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'n8n_user') THEN
    CREATE USER n8n_user WITH PASSWORD '${POSTGRES_PASSWORD}';
  END IF;
END
$$;

-- Grant basic privileges to n8n_user
ALTER USER n8n_user WITH NOCREATEDB NOCREATEROLE;

-- **FIX: Explicitly create the database and set owner to prevent "database does not exist" error**
CREATE DATABASE n8n_production OWNER n8n_user;

-- The subsequent ALTER DATABASE is now redundant but kept for original intent clarity (will run successfully)
ALTER DATABASE n8n_production OWNER TO n8n_user; 

-- ============================================================================
-- n8n SCHEMA AND TABLES
-- ============================================================================

-- Connect to n8n_production database
\c n8n_production

-- Grant schema privileges
GRANT ALL PRIVILEGES ON SCHEMA public TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO n8n_user;

-- ============================================================================
-- EXTENSIONS (AFTER ALTER SYSTEM SETTINGS)
-- ============================================================================

-- Create pg_stat_statements extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- ============================================================================
-- STATISTICS & MONITORING
-- ============================================================================

-- Create monitoring schema
CREATE SCHEMA IF NOT EXISTS monitoring AUTHORIZATION n8n_user;

-- Table to track execution statistics for monitoring
CREATE TABLE IF NOT EXISTS monitoring.execution_stats (
  id SERIAL PRIMARY KEY,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  workflow_id UUID,
  total_executions BIGINT DEFAULT 0,
  successful_executions BIGINT DEFAULT 0,
  failed_executions BIGINT DEFAULT 0,
  average_duration INTERVAL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Table to track n8n events
CREATE TABLE IF NOT EXISTS monitoring.events (
  id SERIAL PRIMARY KEY,
  event_type VARCHAR(100) NOT NULL,
  event_data JSONB,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

GRANT ALL PRIVILEGES ON SCHEMA monitoring TO n8n_user;
GRANT ALL PRIVILEGES ON monitoring.execution_stats TO n8n_user;
GRANT ALL PRIVILEGES ON monitoring.events TO n8n_user;

-- ============================================================================
-- BACKUP & RECOVERY SETTINGS
-- ============================================================================

-- Enable full backup capabilities
ALTER SYSTEM SET wal_level = replica;

-- Archive WAL for point-in-time recovery (if using external archiver)
-- ALTER SYSTEM SET archive_mode = on;
-- ALTER SYSTEM SET archive_command = 'test ! -f /wal_archive/%f && cp %p /wal_archive/%f';
-- ALTER SYSTEM SET archive_timeout = '300';

-- ============================================================================
-- VACUUM & ANALYZE SETTINGS
-- ============================================================================

-- Run initial analyze to create statistics
ANALYZE;

-- ============================================================================
-- CONFIRM SETTINGS
-- ============================================================================

-- Display applied settings
SELECT name, setting FROM pg_settings
WHERE name IN (
  'max_connections',
  'shared_buffers',
  'effective_cache_size',
  'work_mem',
  'maintenance_work_mem',
  'wal_level',
  'autovacuum',
  'shared_preload_libraries'
);

-- ============================================================================
-- RELOAD CONFIGURATION
-- ============================================================================

-- Note: Some settings require PostgreSQL restart to take effect
-- Docker will restart the container after this script runs
SELECT pg_reload_conf();

GRANT pg_monitor TO n8n_user;
