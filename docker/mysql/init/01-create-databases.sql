-- Create databases for Rails and Django
CREATE DATABASE IF NOT EXISTS vibe_rails CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS vibe_django CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Grant permissions (root already has all permissions, but for clarity)
GRANT ALL PRIVILEGES ON vibe_rails.* TO 'root'@'%';
GRANT ALL PRIVILEGES ON vibe_django.* TO 'root'@'%';

FLUSH PRIVILEGES;
