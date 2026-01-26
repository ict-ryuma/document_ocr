-- Create database for Rails
CREATE DATABASE IF NOT EXISTS vibe_rails CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Grant permissions (root already has all permissions, but for clarity)
GRANT ALL PRIVILEGES ON vibe_rails.* TO 'root'@'%';

FLUSH PRIVILEGES;
