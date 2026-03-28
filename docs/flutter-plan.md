# BiMusic Flutter Client Implementation Plan

## 1. Flutter and Dart Version

- **Flutter SDK:** 3.27.x (latest stable channel)
- **Dart SDK:** 3.6.x (bundled with Flutter 3.27)
- **Minimum platform targets:**
  - Android: API 21 (Android 5.0) — covers 99%+ of devices
  - iOS: 13.0 — required by audio_service and flutter_secure_storage
  - Web: All modern evergreen browsers (Chrome, Firefox, Safari, Edge)
  - Windows: Windows 10+ (x64)
  - Linux: Ubuntu 22.04+ / equivalent (x64)
  - macOS: 11.0+ (Big Sur) — deferred for v1 but supported by all chosen packages

Pin Flutter version in CI and recommend using `fvm` (Flutter Version Management) locally to ensure all developers use the same SDK.

## 2. Project Structure

```
bimusic_app/
├── lib/
│   ├── main.dart                     # Entry point, app config, router setup
│   ├── app.dart                      # MaterialApp widget, theme, global providers
│   ├── config/
│   │   ├── api_config.dart           # Base URL, timeouts, endpoints constants
│   │   ├── app_config.dart           # Feature flags, bitrate constants
│   │   └── theme.dart                # Light/dark theme definitions
│   ├── models/
│   │   ├── user.dart                 # User model
│   │   ├── artist.dart               # Artist model (maps from Lidarr ArtistResource)
│   │   ├── album.dart                # Album model (maps from Lidarr AlbumResource)
│   │   ├── track.dart                # Track model
│   │   ├── playlist.dart             # Playlist model
│   │   ├── download_task.dart        # Offline download state model
│   │   └── auth_tokens.dart          # JWT + refresh token pair
│   ├── providers/
│   │   ├── auth_provider.dart        # Auth state, login/logout, token refresh
│   │   ├── player_provider.dart      # Playback state, queue, current track
│   │   ├── library_provider.dart     # Artists, albums, tracks from backend
│   │   ├── playlist_provider.dart    # User playlists CRUD
│   │   ├── search_provider.dart      # Search + Lidarr request state
│   │   ├── download_provider.dart    # Offline download management
│   │   ├── connectivity_provider.dart # Network type monitoring
│   │   └── storage_provider.dart     # Storage usage tracking
│   ├── services/
│   │   ├── api_client.dart           # Dio instance, interceptors, base request methods
│   │   ├── auth_service.dart         # Login, refresh, logout API calls
│   │   ├── music_service.dart        # Library browsing, streaming URL generation
│   │   ├── playlist_service.dart     # Playlist CRUD API calls
│   │   ├── search_service.dart       # Library search + Lidarr request API calls (/library/search, /requests/*)
│   │   ├── download_service.dart     # Background download execution
│   │   ├── audio_service.dart        # Audio session + notification controls
│   │   └── log_service.dart          # File-based logging
│   ├── ui/
│   │   ├── screens/
│   │   │   ├── login_screen.dart
│   │   │   ├── home_screen.dart      # Shell with nav (tabs on mobile, sidebar on desktop/web)
│   │   │   ├── library_screen.dart   # Browse artists/albums
│   │   │   ├── album_detail_screen.dart
│   │   │   ├── artist_detail_screen.dart
│   │   │   ├── playlist_screen.dart
│   │   │   ├── playlist_detail_screen.dart
│   │   │   ├── search_screen.dart
│   │   │   ├── downloads_screen.dart # Manage offline content + storage usage
│   │   │   └── settings_screen.dart
│   │   ├── widgets/
│   │   │   ├── player_bar.dart       # Persistent mini-player at bottom
│   │   │   ├── full_player.dart      # Expanded now-playing view
│   │   │   ├── track_tile.dart       # Reusable track list item
│   │   │   ├── album_card.dart       # Album grid/list item
│   │   │   ├── artist_card.dart
│   │   │   ├── download_indicator.dart
│   │   │   ├── storage_usage_bar.dart
│   │   │   └── adaptive_scaffold.dart # Switches between mobile/desktop layouts
│   │   └── layouts/
│   │       ├── mobile_layout.dart    # Bottom nav + stacked navigation
│   │       ├── desktop_layout.dart   # Sidebar nav + master-detail
│   │       └── breakpoints.dart      # Width breakpoints for layout switching
│   └── utils/
│       ├── constants.dart
│       ├── extensions.dart           # Duration formatting, etc.
│       └── platform_utils.dart       # Platform detection helpers
├── test/
│   ├── unit/                         # Provider + service unit tests
│   ├── widget/                       # Widget tests
│   └── integration/                  # Integration test flows
├── integration_test/                 # Flutter driver / integration_test package
├── pubspec.yaml
├── analysis_options.yaml
└── .github/
    └── workflows/
        └── flutter_ci.yml
```

## 3. Package Selections

| Package | Version | Purpose | Justification |
|---------|---------|---------|---------------|
| `flutter_riverpod` | ^2.6 | State management | Compile-safe, testable, no context dependency. Good fit for a multi-provider app with audio + auth + downloads all needing independent reactive state. Simpler than Bloc for this scale. |
| `riverpod_annotation` | ^2.6 | Code generation for providers | Reduces boilerplate, enforces conventions |
| `dio` | ^5.7 | HTTP client | Interceptor support for JWT refresh, request cancellation for search, multipart for future needs |
| `just_audio` | ^0.9 | Audio playback | Best cross-platform audio: streaming from URL, gapless playback, buffer control. Supports mobile, web, desktop. |
| `just_audio_media_kit` | ^2.1 | Desktop audio backend (libmpv) | Replaces `just_audio_windows` — WMF doesn't support custom HTTP headers on media streams. libmpv has broad codec support. |
| `media_kit_libs_windows_audio` | ^1.0 | libmpv native libs for Windows | Required by `just_audio_media_kit` on Windows. |
| `audio_service` | ^0.18 | Background playback + media controls | Lock screen controls, notification media controls, background audio on mobile. Integrates with just_audio. |
| `audio_session` | ^0.1 | Audio focus management | Handles interruptions (calls, other apps) properly per platform |
| `connectivity_plus` | ^6.1 | Network type detection | Detects WiFi vs cellular vs none. Needed for bitrate selection logic. |
| `flutter_secure_storage` | ^9.2 | Secure token storage | Stores JWT and refresh tokens in platform keychain/keystore. More secure than shared_preferences for auth tokens. |
| `path_provider` | ^2.1 | Platform-specific directories | Needed for offline file storage paths and log file location |
| `isar` | ^4.0 | Local database | Fast, cross-platform embedded DB. Stores download metadata, playlist cache, library cache for offline. No server needed unlike sqflite. |
| `go_router` | ^14.6 | Routing | Declarative routing with deep linking support for web. Integrates well with Riverpod for auth-guarded routes. |
| `cached_network_image` | ^3.4 | Album art caching | Caches cover art images with disk + memory cache |
| `flutter_background_service` | ^5.0 | Background downloads (mobile) | Keeps download service alive when app is backgrounded on mobile. Confirmed by architect as the correct choice for long-running download tasks that need persistent execution rather than OS-scheduled periodic work. |
| `logger` | ^2.4 | Logging | Simple, colorized console output in dev; structured output we pipe to file in prod |
| `freezed` | ^2.5 | Immutable models | Code-generated immutable data classes with copyWith, JSON serialization |
| `json_annotation` | ^4.9 | JSON serialization | Code-generated fromJson/toJson, reduces manual parsing errors |
| `build_runner` | ^2.4 | Code generation | Runs freezed, json_serializable, riverpod_generator |
| `mocktail` | ^1.0 | Testing mocks | Null-safe mocking without codegen, simpler than mockito for Dart |
| `flutter_lints` | (via analysis_options) | Linting | Consistent code style enforcement |

## 4. State Management (Riverpod)

### Architecture

All state is managed through Riverpod providers, organized by domain:

```
AuthNotifier (StateNotifier<AuthState>)
  ├── Manages: login, logout, token storage, auto-refresh
  └── Exposes: isAuthenticated, currentUser, tokens

PlayerNotifier (StateNotifier<PlayerState>)
  ├── Manages: current track, queue, play/pause/seek, shuffle, repeat
  ├── Depends on: AuthProvider (for stream URLs), ConnectivityProvider (for bitrate)
  └── Exposes: currentTrack, isPlaying, position, duration, queue

LibraryNotifier (AsyncNotifier<LibraryState>)
  ├── Manages: artists, albums, tracks from backend
  ├── Depends on: AuthProvider
  └── Exposes: artists, albums, recentlyAdded

PlaylistNotifier (AsyncNotifier<PlaylistState>)
  ├── Manages: user playlists, add/remove tracks
  └── Exposes: playlists, playlistTracks

SearchNotifier (StateNotifier<SearchState>)
  ├── Manages: search query, results, Lidarr music requests
  └── Exposes: results, isSearching, requestStatus

DownloadNotifier (StateNotifier<DownloadState>)  — mobile/desktop only, not initialized on web
  ├── Manages: download queue, progress, storage tracking, device_id
  ├── Depends on: AuthProvider, local DB (Isar), DeviceIdProvider
  └── Exposes: downloads, totalStorageUsed, isDownloading

ConnectivityProvider (StreamProvider<ConnectivityType>)
  └── Exposes: current network type (wifi, mobile, none)
```

### Key Pattern: Provider Scoping for Multi-User

Since multiple users can log in on the same device, all user-specific data (playlists, downloads, library cache) is scoped by user ID. The Isar database collections include a `userId` field, and providers filter by the current authenticated user.

```dart
// Downloads scoped to current user + device (mobile/desktop only)
final userDownloadsProvider = Provider<List<DownloadTask>>((ref) {
  if (kIsWeb) return []; // no offline downloads on web
  final userId = ref.watch(authProvider).currentUser?.id;
  final deviceId = ref.watch(deviceIdProvider);
  final allDownloads = ref.watch(downloadProvider).downloads;
  return allDownloads
    .where((d) => d.userId == userId && d.deviceId == deviceId)
    .toList();
});
```

## 5. Audio Playback

### Stack

```
UI (PlayerBar, FullPlayer)
  ↓ controls
PlayerNotifier (Riverpod)
  ↓ delegates to
AudioPlayerService (wraps just_audio + audio_service)
  ↓ platform media session
audio_service (notification, lock screen, background)
  ↓ actual playback
just_audio (decode + output)
```

### Implementation Details

**Streaming URL Construction:**
The player requests a streaming URL from the backend:
```
GET /api/stream/:trackId?bitrate={128|320}&token=<jwt>
```
The JWT is passed as a `?token=` query parameter rather than an `Authorization` header because `just_audio`'s header-proxy mechanism doesn't work reliably with the libmpv backend (`just_audio_media_kit`). The backend `authenticate` middleware accepts tokens from either the header or the query parameter.

The backend transcodes via ffmpeg and serves the response with HTTP Range header support for seeking. libmpv handles Range requests natively.

**Bitrate Selection:**
```dart
int getStreamBitrate(ConnectivityResult connectivity) {
  switch (connectivity) {
    case ConnectivityResult.wifi:
    case ConnectivityResult.other: // 5G reports as 'other' or 'mobile'
      return 320;
    default:
      return 128;
  }
}
```

Note: `connectivity_plus` cannot distinguish 5G from LTE reliably on all platforms. We will treat WiFi as 320k guaranteed, and for mobile connections, use the `NetworkInformation` API on web and platform channels on Android/iOS to check for 5G when possible. If detection fails, default to 128k (safe fallback).

**Seeking and Progress Bar:**
The backend serves all streams (both passthrough and transcoded) with HTTP Range header support. libmpv handles Range requests natively, so the progress bar is fully draggable and `seek()` works for both streamed and offline content.

**Gapless Playback:**
Use `just_audio`'s `ConcatenatingAudioSource` to queue tracks for gapless album/playlist playback.

**Background Audio (Mobile):**
`audio_service` runs playback in an isolate with a persistent notification showing track info, play/pause/skip controls.

**Desktop/Web:**
No background service needed. `just_audio` plays directly. Media keys handled via `audio_service`'s desktop integration.

**Offline Playback:**
When a track is downloaded, the player uses a `FileAudioSource` pointing to the local file instead of a streaming URL. No bitrate selection needed for offline (always 320k downloaded files).

```dart
AudioSource getSourceForTrack(Track track, int bitrate) {
  // Offline files only available on mobile/desktop (not web)
  if (!kIsWeb) {
    final localPath = downloadService.getLocalPath(track.id);
    if (localPath != null) {
      return AudioSource.file(localPath);
    }
  }
  return AudioSource.uri(
    Uri.parse('${apiConfig.baseUrl}/api/stream/${track.id}?bitrate=$bitrate'),
    headers: {'Authorization': 'Bearer $jwt'},
  );
}
```

## 6. Adaptive Layouts

### Breakpoint Strategy

```dart
class Breakpoints {
  static const double mobile = 0;
  static const double tablet = 600;
  static const double desktop = 1024;
}
```

### Layout Switching

**AdaptiveScaffold** — a wrapper widget that selects layout based on `MediaQuery.sizeOf(context).width`:

| Width | Layout | Navigation | Player |
|-------|--------|------------|--------|
| < 600 | Mobile | Bottom tab bar (5 tabs: Home, Library, Search, Playlists, Settings) | Mini-player bar above tabs, expands to full-screen on tap |
| 600-1023 | Tablet | Bottom tab bar, wider content | Mini-player bar, larger album art |
| >= 1024 | Desktop/Web | Fixed left sidebar with nav items | Persistent bottom bar with full controls + progress + queue |

**Desktop sidebar** shows: user avatar, nav items (Home, Library, Search, Playlists, Downloads [hidden on web], Settings), storage usage indicator at bottom (hidden on web).

**Mobile** uses `Navigator 2.0` via `go_router` with `ShellRoute` for the tab bar + mini-player persistent shell.

**Web-specific:**
- Responsive hover states on clickable elements
- Right-click context menus on tracks (add to playlist, download, etc.)
- Keyboard shortcuts (space = play/pause, arrows = seek, etc.)
- URL-based deep linking (`/album/123`, `/playlist/456`)

**Desktop-specific:**
- Window title updates with current track
- System tray / menu bar integration is out of scope for v1 (low value for small user base)

### Platform Detection

```dart
bool get isMobile => Platform.isAndroid || Platform.isIOS;
bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
bool get isWeb => kIsWeb;
```

## 7. JWT Authentication Client-Side

### Token Storage

- **Mobile/Desktop:** `flutter_secure_storage` (Android Keystore, iOS Keychain, macOS Keychain, Linux libsecret, Windows credential store)
- **Web:** `flutter_secure_storage` with web fallback to encrypted localStorage (acceptable for small user base)

### Auth Flow

```
App Launch
  ↓
Read stored tokens from secure storage
  ↓
tokens exist? ──no──→ Show LoginScreen
  │
  yes
  ↓
Validate refresh token (call /api/auth/refresh)
  ↓
success? ──no──→ Clear tokens, show LoginScreen
  │
  yes
  ↓
Store new JWT + refresh token
  ↓
Navigate to HomeScreen
```

### Dio Interceptor for Auto-Refresh

```dart
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Attach JWT to every request
    final token = authService.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Attempt token refresh
      final refreshed = await authService.refreshToken();
      if (refreshed) {
        // Retry original request with new token
        final retryResponse = await dio.fetch(err.requestOptions);
        handler.resolve(retryResponse);
        return;
      }
      // Refresh failed — force logout
      authNotifier.logout();
    }
    handler.next(err);
  }
}
```

### Concurrent Refresh Protection

Use a `Completer` to ensure only one refresh request runs at a time. Subsequent 401s wait for the in-flight refresh rather than spawning parallel refresh calls.

## 8. REST API Client Layer

### Dio Setup

```dart
final dio = Dio(BaseOptions(
  baseUrl: apiConfig.baseUrl,
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 30),
  // Streaming endpoints get longer timeout overridden per-request
));

dio.interceptors.addAll([
  AuthInterceptor(authService: authService, dio: dio),
  LogInterceptor(logPrint: logService.debug), // only in debug
]);
```

### Service Layer Pattern

Each service class takes `Dio` as a dependency and encapsulates one API domain:

```dart
class MusicService {
  final Dio _dio;
  MusicService(this._dio);

  Future<List<Artist>> getArtists() async {
    final response = await _dio.get('/api/library/artists');
    return (response.data as List).map((j) => Artist.fromJson(j)).toList();
  }

  Future<Artist> getArtist(int id) async {
    final response = await _dio.get('/api/library/artists/$id');
    return Artist.fromJson(response.data);
  }

  Future<List<Album>> getArtistAlbums(int artistId) async {
    final response = await _dio.get('/api/library/artists/$artistId/albums');
    return (response.data as List).map((j) => Album.fromJson(j)).toList();
  }

  Future<Album> getAlbum(int id) async {
    final response = await _dio.get('/api/library/albums/$id');
    return Album.fromJson(response.data);
  }

  Future<List<Track>> getAlbumTracks(int albumId) async {
    final response = await _dio.get('/api/library/albums/$albumId/tracks');
    return (response.data as List).map((j) => Track.fromJson(j)).toList();
  }

  Future<List<SearchResult>> searchLibrary(String query) async {
    final response = await _dio.get('/api/library/search', queryParameters: {'term': query});
    return (response.data as List).map((j) => SearchResult.fromJson(j)).toList();
  }

  String getStreamUrl(int trackId, int bitrate) {
    return '${_dio.options.baseUrl}/api/stream/$trackId?bitrate=$bitrate';
  }

  String getArtistImageUrl(int artistId) {
    return '${_dio.options.baseUrl}/api/library/artists/$artistId/image';
  }

  String getAlbumImageUrl(int albumId) {
    return '${_dio.options.baseUrl}/api/library/albums/$albumId/image';
  }
}
```

**Endpoints consumed by the Flutter client** (aligned with architecture-plan.md):

| Method | Path | Purpose |
|--------|------|---------|
| **Auth** | | |
| POST | `/api/auth/login` | Login, receive JWT + refresh token |
| POST | `/api/auth/refresh` | Rotate refresh token, get new access token |
| POST | `/api/auth/logout` | Revoke refresh token |
| GET | `/api/auth/me` | Get current user profile |
| **Library** | | |
| GET | `/api/library/artists` | List all artists |
| GET | `/api/library/artists/:id` | Artist detail |
| GET | `/api/library/artists/:id/albums` | Albums for artist |
| GET | `/api/library/artists/:id/image` | Proxy artist image from Lidarr |
| GET | `/api/library/albums/:id` | Album detail |
| GET | `/api/library/albums/:id/tracks` | Tracks for album |
| GET | `/api/library/albums/:id/image` | Proxy album cover from Lidarr |
| GET | `/api/library/tracks/:id` | Track detail + file info |
| GET | `/api/library/search?term=` | Search artists/albums in library |
| **Streaming** | | |
| GET | `/api/stream/:trackId?bitrate=` | Stream transcoded audio (128 or 320) |
| **Requests (Lidarr)** | | |
| GET | `/api/requests` | List user's pending requests with live Lidarr status |
| GET | `/api/requests/search?term=` | Search for new artists/albums to request |
| POST | `/api/requests/artist` | Add artist to Lidarr + trigger search |
| POST | `/api/requests/album` | Add/monitor album in Lidarr + trigger search |
| **Playlists** | | |
| GET | `/api/playlists` | List current user's playlists |
| POST | `/api/playlists` | Create playlist |
| GET | `/api/playlists/:id` | Get playlist with tracks |
| PATCH | `/api/playlists/:id` | Update playlist name/description |
| DELETE | `/api/playlists/:id` | Delete playlist |
| POST | `/api/playlists/:id/tracks` | Add track(s) to playlist |
| DELETE | `/api/playlists/:id/tracks/:trackId` | Remove track from playlist |
| PATCH | `/api/playlists/:id/tracks/reorder` | Reorder tracks |
| **Offline Downloads** (mobile/desktop only) | | |
| GET | `/api/downloads?deviceId=` | List downloads for user+device |
| POST | `/api/downloads` | Request track for offline `{ trackId, deviceId, bitrate }` |
| DELETE | `/api/downloads/:id` | Remove offline download record |
| GET | `/api/downloads/:id/file` | Download the transcoded file for offline storage |
| **Health** | | |
| GET | `/api/health` | Connectivity check, used on app startup and network recovery |

## 9. Offline Download Management

**Note: Offline downloads are available on mobile and desktop only. On web, the download UI is hidden and the download provider is not initialized.** The web client streams all content.

### Device ID

Each device generates a stable `deviceId` on first launch (UUID v4) and stores it in `flutter_secure_storage`. This ID is sent with all download-related API calls so the backend can scope downloads to `(userId, deviceId)`. The same user on two devices maintains separate offline libraries.

```dart
Future<String> getOrCreateDeviceId() async {
  final storage = ref.read(secureStorageProvider);
  var deviceId = await storage.read(key: 'device_id');
  if (deviceId == null) {
    deviceId = const Uuid().v4();
    await storage.write(key: 'device_id', value: deviceId);
  }
  return deviceId;
}
```

### Architecture

```
User taps "Download Album"
  ↓
DownloadNotifier enqueues tracks
  → POST /api/downloads { trackId, deviceId, bitrate: 320 } for each track
  → Backend creates offline_downloads records (status: pending)
  → Isar local DB also tracks state client-side
  ↓
DownloadService picks up pending tasks (max 2 concurrent)
  ↓
GET /api/downloads/:id/file with auth header
  ↓
Save to: <app_documents>/<userId>/music/<artistId>/<albumId>/<trackId>.mp3
  ↓
Update Isar record (status: completed, filePath, fileSize)
  ↓
DownloadNotifier emits updated state → UI rebuilds
```

### Storage Organization

```
<app_documents>/
  └── <userId>/
      └── music/
          └── <artistId>/
              └── <albumId>/
                  ├── <trackId>.mp3
                  └── cover.jpg
```

Per-user directories ensure downloads are isolated between users on the same device.

### Download States

```dart
enum DownloadStatus { pending, downloading, completed, failed }

@freezed
class DownloadTask with _$DownloadTask {
  const factory DownloadTask({
    required String serverId,   // ID from backend offline_downloads table
    required int trackId,
    required int albumId,
    required int artistId,
    required String userId,
    required String deviceId,   // stable device identifier
    required DownloadStatus status,
    double? progress,           // 0.0 - 1.0
    String? filePath,
    int? fileSizeBytes,
    DateTime? completedAt,
    String? errorMessage,
  }) = _DownloadTask;
}
```

### Storage Usage Display

```dart
final storageUsageProvider = Provider<StorageUsage>((ref) {
  final downloads = ref.watch(userDownloadsProvider);
  final totalBytes = downloads
    .where((d) => d.status == DownloadStatus.completed)
    .fold<int>(0, (sum, d) => sum + (d.fileSizeBytes ?? 0));
  return StorageUsage(
    usedBytes: totalBytes,
    trackCount: downloads.where((d) => d.status == DownloadStatus.completed).length,
  );
});
```

This is surfaced in the Downloads screen and in the desktop sidebar as a small usage bar. The user manages their own storage — we show the numbers but don't impose limits (per requirements: "The user should generally be trusted to manage their storage").

### Background Downloads (Mobile)

On mobile, `flutter_background_service` keeps the download service alive when the app is backgrounded, providing persistent execution for long-running download tasks. Downloads are paused when connectivity is lost and resumed when restored. On desktop, downloads only run while the app is in the foreground (acceptable for small user base). **On web, offline downloads are not available.**

### Removing Downloads

Users can remove individual tracks, entire albums, or all downloads. Removing: (1) calls `DELETE /api/downloads/:id` to remove the server-side record, (2) deletes the local file, (3) updates the Isar record.

## 10. Bitrate Selection Logic

```dart
final bitrateProvider = Provider<int>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return switch (connectivity) {
    ConnectivityResult.wifi => 320,
    ConnectivityResult.mobile => _isFiveG() ? 320 : 128,
    ConnectivityResult.ethernet => 320,
    _ => 128,  // unknown or none — safe fallback
  };
});
```

**5G Detection Caveats:**
- Android: Use `TelephonyManager.getDataNetworkType()` via a small platform channel to check for `NETWORK_TYPE_NR` (5G NR).
- iOS: Use `CTTelephonyNetworkInfo` via platform channel to check for `CTRadioAccessTechnologyNR`.
- Web: `navigator.connection.effectiveType` only gives `4g` at best — we cannot detect 5G on web. Default to 128k on mobile web.
- Desktop: Always WiFi or ethernet, always 320k.

Keep this simple: if detection fails or is ambiguous, use 128k. Users on fast mobile connections will still get acceptable quality at 128k, and offline downloads are always 320k.

## 11. File-Based Logging

### Implementation

```dart
class LogService {
  late final File _logFile;
  final _buffer = StringBuffer();
  Timer? _flushTimer;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    final logDir = Directory('${dir.path}/logs');
    await logDir.create(recursive: true);
    final date = DateTime.now().toIso8601String().split('T').first;
    _logFile = File('${logDir.path}/bimusic_$date.log');
  }

  void log(LogLevel level, String message, [Object? error]) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] [${level.name}] $message';
    if (error != null) {
      _buffer.writeln('$line | error=$error');
    } else {
      _buffer.writeln(line);
    }
    // Batch writes: flush every 5 seconds or when buffer > 4KB
    _flushTimer ??= Timer(const Duration(seconds: 5), _flush);
    if (_buffer.length > 4096) _flush();
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty) return;
    _logFile.writeAsStringSync(_buffer.toString(), mode: FileMode.append);
    _buffer.clear();
  }

  void debug(String msg) => log(LogLevel.debug, msg);
  void info(String msg) => log(LogLevel.info, msg);
  void warn(String msg) => log(LogLevel.warn, msg);
  void error(String msg, [Object? err]) => log(LogLevel.error, msg, err);
}

enum LogLevel { debug, info, warn, error }
```

### What Gets Logged

- API requests and responses (status code, duration — not body or tokens)
- Auth events (login, logout, refresh success/fail)
- Playback events (play, pause, track change, errors)
- Download events (start, progress milestones, complete, fail)
- Errors and exceptions with stack traces

### Log Rotation

Daily log files (`bimusic_2026-03-27.log`). On app startup, delete log files older than 7 days.

### Web Platform

On web, logging writes to an in-memory ring buffer (last 1000 entries) since file access is restricted. Logs can be exported via a "Download Logs" button in Settings.

## 12. Test Approach

### Unit Tests (`test/unit/`)

**What:** Test providers, services, and models in isolation.

| Test Target | Coverage Focus |
|-------------|---------------|
| `AuthNotifier` | Login flow, token refresh, logout, expired token handling |
| `PlayerNotifier` | Play/pause, queue management, track advancement, shuffle, repeat |
| `DownloadNotifier` | Enqueue, progress updates, completion, failure handling, storage calc |
| `BitrateProvider` | Returns correct bitrate for each connectivity type |
| `AuthInterceptor` | 401 triggers refresh, retry succeeds, concurrent refresh protection |
| `MusicService` | API calls map to correct endpoints, response parsing |
| Models (freezed) | fromJson/toJson roundtrip, copyWith |

**Approach:** Use `mocktail` to mock Dio, secure storage, and platform services. Riverpod's `ProviderContainer` for testing providers without widgets.

### Widget Tests (`test/widget/`)

| Test Target | Coverage Focus |
|-------------|---------------|
| `LoginScreen` | Form validation, error display, loading state |
| `TrackTile` | Renders track info, tap triggers play, long-press shows menu |
| `PlayerBar` | Shows current track, play/pause button state, progress bar |
| `AlbumDetailScreen` | Renders album info, track list, download button state |
| `AdaptiveScaffold` | Correct layout at each breakpoint |
| `DownloadsScreen` | Storage usage display, download list, remove action |

**Approach:** Use `ProviderScope` overrides to inject mock state. Test with `tester.pumpWidget()`.

### Integration Tests (`integration_test/`)

| Test Flow | Steps |
|-----------|-------|
| Auth flow | Login with credentials → navigate to home → logout → back at login |
| Browse & play | Login → browse library → tap album → tap track → verify playback starts |
| Search & request | Login → search → view results → request new album via Lidarr |
| Offline flow (mobile/desktop only) | Login → download album → go offline → play downloaded track |
| Playlist management | Create playlist → add tracks → reorder → remove track → delete playlist |

**Approach:** Use `integration_test` package. Run against a local backend (or mock server via `shelf` for CI). These tests verify end-to-end flows.

### CI Integration

See GitHub Actions workflow below. Tests run on every push and PR.

## 13. GitHub Actions CI for Flutter

```yaml
# .github/workflows/flutter_ci.yml
name: Flutter CI

on:
  push:
    branches: [main]
    paths:
      - 'bimusic_app/**'
  pull_request:
    branches: [main]
    paths:
      - 'bimusic_app/**'

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: bimusic_app
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.27.x'
          channel: stable
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Generate code (freezed, json_serializable, riverpod)
        run: dart run build_runner build --delete-conflicting-outputs

      - name: Analyze
        run: flutter analyze --fatal-infos

      - name: Run unit and widget tests
        run: flutter test --coverage

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          file: bimusic_app/coverage/lcov.info
          flags: flutter

  build-android:
    runs-on: ubuntu-latest
    needs: analyze-and-test
    defaults:
      run:
        working-directory: bimusic_app
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.27.x'
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter build apk --release

  build-web:
    runs-on: ubuntu-latest
    needs: analyze-and-test
    defaults:
      run:
        working-directory: bimusic_app
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.27.x'
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter build web

  build-windows:
    runs-on: windows-latest
    needs: analyze-and-test
    defaults:
      run:
        working-directory: bimusic_app
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.27.x'
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter build windows --release

  build-linux:
    runs-on: ubuntu-latest
    needs: analyze-and-test
    defaults:
      run:
        working-directory: bimusic_app
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.27.x'
          channel: stable
          cache: true
      - run: |
          sudo apt-get update
          sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter build linux --release
```

**Notes:**
- macOS/iOS builds require `macos-latest` runners which are expensive on GitHub Actions. For a small user base, build locally or add these jobs only when needed.
- Integration tests against the real backend run separately (see QA/test plan) since they require the backend to be running.
- Flutter version pinned to `3.27.x` (latest stable at time of writing) for reproducibility.

## 14. Key Implementation Patterns

### Error Handling

Use a typed `Result` pattern for service calls:

```dart
sealed class Result<T> {
  const Result();
}
class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}
class Failure<T> extends Result<T> {
  final String message;
  final int? statusCode;
  const Failure(this.message, {this.statusCode});
}
```

Providers translate `Result` into UI state (data, loading, error) using Riverpod's `AsyncValue`.

### Dependency Injection

All services are registered as Riverpod providers, allowing easy override in tests:

```dart
final dioProvider = Provider<Dio>((ref) => createDio(ref));
final musicServiceProvider = Provider<MusicService>((ref) =>
  MusicService(ref.read(dioProvider)),
);
```

### Image Caching

Album art URLs go through `CachedNetworkImage` with auth headers. On offline, the cached version serves from disk. For downloaded albums, the cover art is also saved locally.

### Startup Sequence

```
main() → WidgetsFlutterBinding.ensureInitialized()
  → LogService.init()
  → Isar.open()
  → Read stored auth tokens
  → Create ProviderScope with overrides
  → runApp(BiMusicApp())
  → GoRouter redirects to login or home based on auth state
```
