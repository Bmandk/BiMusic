# BiMusic UX Plan

## Table of Contents

1. [Navigation Architecture](#1-navigation-architecture)
2. [Authentication Flows](#2-authentication-flows)
3. [Home / Library Screen](#3-home--library-screen)
4. [Music Browsing & Search](#4-music-browsing--search)
5. [Playback — Mini-Player & Full-Screen](#5-playback--mini-player--full-screen)
6. [Playlists](#6-playlists)
7. [Offline Downloads & Storage Management](#7-offline-downloads--storage-management)
8. [Lidarr Request Flow](#8-lidarr-request-flow)
9. [Settings](#9-settings)
10. [Platform Layout Differences](#10-platform-layout-differences)
11. [Accessibility](#11-accessibility)
12. [Network & Offline State Handling](#12-network--offline-state-handling)

---

## 1. Navigation Architecture

### Mobile (Phone)

- **Bottom navigation bar** with 4 tabs: Home, Search, Library, Settings
- **Mini-player** sits above the bottom nav bar, always visible when audio is playing
- Tapping the mini-player expands to a full-screen player (slide-up transition)
- All drill-down navigation uses standard push/pop stack per tab

### Tablet

- Same as mobile but with a wider layout: master-detail where appropriate (e.g., playlist list on left, tracks on right)

### Desktop / Web

- **Left sidebar** (persistent, collapsible) with navigation items: Home, Search, Library, Playlists, Settings
- **Main content area** fills the remaining space
- **Bottom bar** spans full width: mini-player with playback controls, progress bar, volume slider, queue toggle
- Right panel (toggle-able) for play queue

---

## 2. Authentication Flows

### 2.1 Login Screen

**Layout:** Centered card on all platforms. Simple and clean.

- **Fields:** Username, Password
- **Actions:** "Sign In" button
- **Behavior:**
  - On success: receive JWT access token + refresh token, navigate to Home
  - On failure: inline error below the form ("Invalid username or password")
  - No "remember me" checkbox — refresh tokens handle persistence
  - Password field has a show/hide toggle

**First-time setup:** If the backend has no users configured, the login screen shows a "Create Admin Account" flow instead (username + password + confirm password). This only appears once.

### 2.2 Session Management

- Access tokens are short-lived (15 min). Refresh tokens are long-lived (30 days).
- Token refresh happens silently in the background. The user never sees it.
- **Session expiry flow:**
  1. If a refresh token expires or is revoked, the user sees a modal overlay: "Your session has expired. Please sign in again."
  2. Modal has a single "Sign In" button that navigates to the login screen.
  3. Any in-progress playback pauses. Offline-downloaded content remains accessible for playback but no new streaming or API calls succeed until re-authenticated.

### 2.3 Logout

- Located in Settings screen
- Tapping "Sign Out" shows a confirmation dialog: "Are you sure? Offline downloads on this device will be kept."
- On confirm: clear tokens, stop playback, navigate to login screen
- Offline files are NOT deleted on logout (they belong to the user/device pair and are available after re-login)

### 2.4 Multi-User

- Each user logs in independently. The app stores credentials per user.
- No user-switching UI — users log out and log back in as a different user. This keeps things simple for the small user count.

---

## 3. Home / Library Screen

### 3.1 Home Tab (Default Landing)

**Purpose:** Quick access to recently played and new additions.

**Sections (vertical scroll):**

1. **Recently Played** — horizontal scrollable row of album art cards (last 20 items). Tapping opens the album/playlist.
2. **Recently Added** — horizontal scrollable row of albums recently added to the server. Pulled from the library.
3. **Your Playlists** — horizontal scrollable row of user's playlists. "See All" link navigates to full playlist list.

**Mobile:** Single column, each section is a horizontal scroll row.
**Desktop/Web:** Wider cards, up to 2 rows visible per section before scrolling. Grid layout for larger screens.

### 3.2 Library Tab

**Purpose:** Browse all available music.

**Sub-tabs at top:** Artists | Albums | Songs

- **Artists view:** Alphabetical grid of artist cards (image + name). Tapping opens Artist Detail.
- **Albums view:** Grid of album art with album title and artist name below. Sortable by: name, artist, date added, year.
- **Songs view:** Scrollable list of all tracks. Columns: title, artist, album, duration. Sortable by each column.

**Artist Detail Screen:**
- Hero section: artist image, name, genre tags
- Sections: Albums (grid), Singles/EPs (grid), Appears On (grid)
- Each album card shows: cover art, title, year, track count
- Tapping an album opens Album Detail

**Album Detail Screen:**
- Header: large album art, album title, artist name (tappable to go to artist), year, genre, total duration
- Action row: Play, Shuffle, Add to Playlist, Download for Offline (icon button)
- Track list: numbered rows with title, duration, explicit tag if applicable
- Each track row has: tap to play, long-press/right-click for context menu (Add to Playlist, Add to Queue, Download, Go to Artist)

---

## 4. Music Browsing & Search

### 4.1 Search Screen

**Layout:**
- Persistent search text field at the top with auto-focus on mobile when tab is selected
- **Before typing:** Show recent searches (clearable list) and browsing suggestions
- **While typing (debounced 300ms):** Show results grouped into sections

**Search Results Sections:**
1. **Artists** — top 3-5 matches, horizontal row or vertical list
2. **Albums** — top 3-5 matches
3. **Songs** — top 5-10 matches
4. Each section has a "See All" link to view full results for that category

**Search scopes:**
- Local library search is the default (fast, searches the BiMusic backend index)
- "Search on Lidarr" button appears below local results, or when local results are empty. This triggers a Lidarr lookup (see section 8).

**Desktop/Web:** Search field is in the top bar (always accessible), results appear in the main content area.
**Mobile:** Search is a dedicated tab. Tapping the search field brings up the keyboard.

### 4.2 Filters

- On Library views, a filter chip bar allows filtering by genre, year range
- Keep it minimal: only add filters that the Lidarr metadata supports

---

## 5. Playback — Mini-Player & Full-Screen

### 5.1 Mini-Player

**Visible:** Whenever a track is loaded (playing or paused). Sticks to the bottom of the screen above the nav bar (mobile) or as a bottom bar (desktop/web).

**Mobile mini-player contents:**
- Album art thumbnail (40x40)
- Track title + artist (truncated with ellipsis)
- Play/Pause button
- Next track button
- Progress bar (thin, at the very top edge of the mini-player)

**Desktop/Web bottom bar contents:**
- Left: Album art thumbnail, track title, artist name, heart/favorite button
- Center: Previous, Play/Pause, Next, Shuffle, Repeat buttons + progress bar with timestamps
- Right: Volume slider, queue toggle button, bitrate indicator badge

**Interaction:**
- Mobile: Tap anywhere on the mini-player (except buttons) to expand to full-screen player
- Desktop: No full-screen expansion; the bottom bar is always visible. Clicking album art opens a "Now Playing" view in the main content area.

### 5.2 Full-Screen Player (Mobile Only)

**Opened by:** Tapping the mini-player. Slide-up transition.

**Layout (vertical stack, centered):**
- Drag handle at top (to swipe down to dismiss)
- Large album art (fills ~60% of width, centered)
- Track title (large text)
- Artist name (tappable, navigates to artist)
- Album name (smaller text, tappable, navigates to album)
- Progress bar (draggable) with elapsed / remaining timestamps
- Control row: Shuffle, Previous, Play/Pause (large), Next, Repeat
- Secondary row: Heart/Favorite, Add to Playlist, Queue, Bitrate badge, Overflow menu (share, go to album, go to artist)

**Gestures:**
- Swipe down: dismiss back to mini-player
- Swipe left/right on album art: next/previous track (with crossfade animation on art)

### 5.3 Play Queue

**Mobile:** Accessible from the full-screen player via queue icon. Opens as a bottom sheet showing the upcoming tracks. Tracks are reorderable via drag handles. Swipe to remove.

**Desktop/Web:** Toggle-able right panel. Shows current track highlighted, upcoming queue below. Drag to reorder, click X to remove.

### 5.4 Bitrate Indicator

- A small badge visible on the player (e.g., "320k" or "128k")
- Automatically reflects the current streaming quality based on network type
- WiFi/5G = 320 kbps, other cellular = 128 kbps
- Offline-downloaded tracks show "Offline" badge instead
- No manual quality override (keeps UX simple per spec)

---

## 6. Playlists

### 6.1 Playlist List Screen

**Accessed from:** Library tab > "Playlists" section, or sidebar on desktop.

**Layout:** Vertical list of playlists. Each row shows:
- Playlist cover (auto-generated mosaic of first 4 album arts, or user-selected)
- Playlist name
- Track count
- Overflow menu: Rename, Delete, Download for Offline

**Actions:**
- "New Playlist" button (floating action button on mobile, button at top on desktop)
- Tap a playlist to open Playlist Detail

### 6.2 Playlist Detail Screen

**Layout:** Same structure as Album Detail but for a playlist.
- Header: playlist art, name, creator, track count, total duration
- Action row: Play, Shuffle, Download for Offline, Edit
- Track list: ordered rows, each with drag handle (in edit mode), track title, artist, album, duration
- Context menu per track: Remove from Playlist, Add to Queue, Go to Album, Go to Artist

### 6.3 Creating & Editing Playlists

- **Create:** Tapping "New Playlist" opens a dialog/sheet with a name text field. Playlist is created empty.
- **Add tracks:** From any track context menu > "Add to Playlist" > shows a list of existing playlists + "New Playlist" option
- **Reorder:** In edit mode, tracks have drag handles. Commit order on exiting edit mode.
- **Remove tracks:** Swipe-to-remove (mobile) or click X (desktop) in edit mode
- **Rename:** From playlist overflow menu or long-press on playlist name in detail view
- **Delete:** Confirmation dialog: "Delete playlist '[name]'? This cannot be undone."

---

## 7. Offline Downloads & Storage Management

### 7.1 Downloading Content

**What can be downloaded:**
- Individual tracks (from track context menu)
- Entire albums (from Album Detail action row)
- Entire playlists (from Playlist Detail action row)

**Download behavior:**
- Downloads happen in the background at 320k bitrate regardless of current network
- Downloads only proceed on WiFi (to avoid consuming mobile data). If not on WiFi, downloads queue and wait.
- A small download icon/badge appears on items that are downloaded or in progress

**Visual states for download icon:**
- No icon: not downloaded
- Arrow-down outline: available for download (shown on hover/long-press context menus only, not cluttering the default view)
- Circular progress: downloading
- Filled checkmark/arrow: downloaded and available offline
- These states appear on album cards, playlist cards, and individual track rows

### 7.2 Download Management Screen

**Accessed from:** Settings > "Offline Downloads" or a dedicated "Downloads" entry in the sidebar (desktop)

**Layout:**
- **Storage usage bar** at top: visual bar showing used / total device storage (e.g., "2.3 GB used of 64 GB"). This is the primary storage visibility mechanism.
- **Downloaded content list:** grouped by Albums and Playlists
  - Each entry shows: name, artist, size on disk, download date
  - Swipe or select to delete (reclaim storage)
- **"Remove All Downloads" button** at bottom with confirmation dialog
- **Auto-download toggle** for playlists: when enabled, new tracks added to a playlist are automatically downloaded

### 7.3 Storage Visibility

Per the spec, users should be trusted to manage their own storage, but current usage should be easily accessible.

- **Settings screen:** Shows total offline storage used prominently (e.g., "Offline Music: 2.3 GB")
- **Download management screen:** Detailed breakdown as described above
- **No storage limits enforced by the app** — users manage their own device storage
- **Low storage warning:** If device storage drops below 500 MB, show a non-blocking banner: "Your device is running low on storage. Consider removing some offline downloads."

---

## 8. Lidarr Request Flow

### 8.1 Discovering New Music via Lidarr

**Entry point:** Search screen, when:
1. Local results are empty or insufficient — a "Search Lidarr for '[query]'" button appears
2. User explicitly taps "Search on Lidarr" toggle/button

**Lidarr Search Results Screen:**
- Results come from the Lidarr `/api/v1/artist/lookup` and `/api/v1/album/lookup` endpoints
- Displayed similarly to local search results but with a distinct visual treatment:
  - Section header: "Results from Lidarr" with a Lidarr icon
  - Artist cards and album cards in the same format but with a "Request" action button instead of "Play"

### 8.2 Requesting an Artist or Album

**Flow:**
1. User taps "Request" on an artist or album from Lidarr search results
2. Confirmation dialog: "Request '[Album/Artist Name]'? Lidarr will search for and download this music. It may take some time to become available."
3. On confirm: the app calls the backend, which proxies to Lidarr's API to add the artist/album and trigger a search
4. A toast notification confirms: "Requested! You'll find it in your library once it's ready."
5. The requested item appears in a "Pending Requests" section (see below)

### 8.3 Pending Requests View

**Accessed from:** Library tab > "Requests" section, or a badge on the Library tab icon

**Layout:** Simple list of pending requests showing:
- Artist/Album name and cover art
- Status: "Searching...", "Downloading...", "Available" (with animation/highlight when newly available)
- Timestamp of request

**Behavior:**
- Polls the backend periodically (every 60 seconds when the screen is visible) or uses a simple refresh-on-open approach
- When a requested album becomes available, it moves to the user's library automatically
- Optional: push notification "Your requested album '[name]' is now available!" (if notifications are implemented later)

---

## 9. Settings

### 9.1 Settings Screen Layout

**Sections:**

1. **Account**
   - User display name
   - "Sign Out" button

2. **Playback**
   - (Informational) "Streaming quality adapts automatically: 320 kbps on WiFi/5G, 128 kbps on cellular"
   - Gapless playback toggle (if supported)

3. **Offline Downloads**
   - Storage used: "2.3 GB" (tappable, opens Download Management screen)
   - "Download on WiFi only" toggle (default: on)
   - "Manage Downloads" link to the Download Management screen

4. **About**
   - App version
   - Backend version (fetched from API)
   - Licenses / Open Source

**Desktop/Web:** Settings is a page in the main content area, accessed from the sidebar. Wider layout uses a two-column format (labels on left, controls on right).

**Mobile:** Standard scrollable settings list with grouped sections.

---

## 10. Platform Layout Differences

### Mobile (Phone)

| Aspect | Behavior |
|---|---|
| Navigation | Bottom tab bar (4 tabs) |
| Player | Mini-player above tab bar; full-screen player on tap |
| Queue | Bottom sheet from full-screen player |
| Search | Dedicated tab, auto-focus text field |
| Context menus | Long-press to open |
| Gestures | Swipe down to dismiss full-screen player, swipe left/right for next/prev track |
| Layout | Single-column, vertical scroll |

### Tablet

| Aspect | Behavior |
|---|---|
| Navigation | Bottom tab bar or side rail (adaptive based on width) |
| Player | Same as phone but with wider mini-player |
| Layout | Master-detail for playlists and artist views |
| Queue | Side panel or bottom sheet |

### Desktop (Windows, macOS, Linux)

| Aspect | Behavior |
|---|---|
| Navigation | Left sidebar (collapsible) |
| Player | Persistent bottom bar with full controls |
| Queue | Toggle-able right panel |
| Search | Integrated in top bar, always accessible |
| Context menus | Right-click |
| Keyboard shortcuts | Space (play/pause), arrows (seek), Ctrl+F (search), Ctrl+N (new playlist) |
| Window management | Resizable, min width ~800px. Sidebar collapses to icons at narrow widths. |

### Web

| Aspect | Behavior |
|---|---|
| Navigation | Same as desktop |
| Player | Same as desktop |
| Differences from desktop | No offline downloads (web storage is unreliable). Downloads section hidden. Bitrate note: always streams at quality matching connection. |

---

## 11. Accessibility

- All interactive elements have semantic labels for screen readers
- Minimum touch target size: 48x48 dp on mobile
- Color contrast: WCAG AA minimum (4.5:1 for text)
- Focus indicators visible for keyboard navigation (desktop/web)
- Player controls are fully keyboard-accessible
- Album art has alt text: "[Album Name] by [Artist Name] album cover"
- Progress bar is adjustable via keyboard (arrow keys for 5-second increments)
- Announce track changes to screen readers: "Now playing [Track] by [Artist]"

---

## 12. Network & Offline State Handling

### Online State

- Normal operation. All features available.
- Streaming quality automatically adapts to network type (WiFi/5G = 320k, other = 128k)

### Offline / No Network

- **Playback:** Only downloaded tracks are playable. Non-downloaded tracks in queue are skipped with a brief toast: "Track unavailable offline, skipping."
- **Library browsing:** The library view shows all content but non-downloaded items are visually dimmed (reduced opacity). Tapping a non-downloaded item shows: "This content is not available offline."
- **Search:** Local search works against cached metadata. Lidarr search is disabled with a message: "Search requires an internet connection."
- **Downloads:** Queued downloads pause. Resume automatically when connection is restored.
- **Banner:** A subtle, non-intrusive banner at the top of the screen: "You're offline. Some features are unavailable." Dismissable, reappears on navigation.

### Degraded Network

- If streaming buffers frequently, no automatic quality downgrade beyond the WiFi/cellular rule. Keep UX simple.
- If a stream fails to load after 10 seconds, show: "Unable to play. Check your connection." with a "Retry" button.

---

## Screen Inventory Summary

| Screen | Description |
|---|---|
| Login | Username/password form, error handling, first-time admin setup |
| Home | Recently played, recently added, quick playlist access |
| Library — Artists | Grid of all artists |
| Library — Albums | Grid of all albums with sort options |
| Library — Songs | List of all songs with sort options |
| Artist Detail | Artist info, discography sections |
| Album Detail | Album info, track listing, play/download actions |
| Search | Text input, local results, Lidarr search option |
| Lidarr Search Results | External results with "Request" actions |
| Pending Requests | List of user's Lidarr requests with status |
| Full-Screen Player | Large art, controls, progress, metadata (mobile) |
| Queue | Upcoming tracks, reorder/remove |
| Playlist List | All user playlists |
| Playlist Detail | Playlist tracks, play/download/edit actions |
| Download Management | Storage bar, downloaded content list, bulk actions |
| Settings | Account, playback info, storage, about |
