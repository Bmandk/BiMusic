// Set environment variables before any module is imported.
// This file runs as a Vitest setupFile for the integration project.
import os from 'os';

process.env['PORT'] = '3099';
process.env['NODE_ENV'] = 'test';
process.env['JWT_ACCESS_SECRET'] = 'integration-test-access-secret-32-chars';
process.env['JWT_REFRESH_SECRET'] = 'integration-test-refresh-secret-32chars';
process.env['JWT_ACCESS_EXPIRY'] = '15m';
process.env['JWT_REFRESH_EXPIRY'] = '30d';
process.env['DB_PATH'] = ':memory:';
process.env['LIDARR_URL'] = 'http://localhost:8686';
process.env['LIDARR_API_KEY'] = 'test-api-key';
// Tests create fixture files under os.tmpdir(), so the library path must match.
process.env['MUSIC_LIBRARY_PATH'] = os.tmpdir();
process.env['OFFLINE_STORAGE_PATH'] = './data/offline';
process.env['ADMIN_USERNAME'] = 'admin';
process.env['ADMIN_PASSWORD'] = 'adminpassword123';
process.env['HLS_CACHE_DIR'] = '/tmp/bimusic-hls-test';
process.env['HLS_SEGMENT_SECONDS'] = '6';
