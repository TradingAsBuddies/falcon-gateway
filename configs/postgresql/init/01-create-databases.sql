-- 01-create-databases.sql
-- Runs once on first container start (empty data volume)
-- The 'falcon' database is auto-created by POSTGRES_DB env var
-- Schema tables are created at runtime by falcon-core's db_manager.py:init_schema()

-- Create additional databases
CREATE DATABASE finviz;

-- Grant privileges to falcon user
GRANT ALL PRIVILEGES ON DATABASE finviz TO falcon;

-- Performance tuning for small/medium workloads
ALTER SYSTEM SET shared_buffers = '128MB';
ALTER SYSTEM SET effective_cache_size = '384MB';
ALTER SYSTEM SET max_connections = 100;
