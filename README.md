# BiMusic

## Running

### Backend

cd backend
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use --lts
cp .env.example .env   # first time only — fill in secrets
npm ci                 # first time only
npm run dev

The backend starts on http://localhost:3000.

Required .env values:
- JWT_ACCESS_SECRET — ≥32 chars
- JWT_REFRESH_SECRET — ≥32 chars
- ADMIN_PASSWORD — ≥8 chars
- LIDARR_BASE_URL + LIDARR_API_KEY — point to your Lidarr instance

### Flutter Client

cd bimusic_app
export PATH="/c/dev/flutter/bin:$PATH"
flutter pub get        # first time only
dart run build_runner build --delete-conflicting-outputs  # first time only
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:3000

## Running Tests

### Backend:
cd backend
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use --lts
npm test               # all tests
npm run test:unit      # unit only
npm run test:integration  # integration only

### Flutter:
cd bimusic_app
export PATH="/c/dev/flutter/bin:$PATH"
flutter test

### Health Check

Once backend is running:
curl http://localhost:3000/api/health

Note: The app requires a running Lidarr instance for library features to work. Without it, auth and health endpoints work but library/stream routes will return errors.