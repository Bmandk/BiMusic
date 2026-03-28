import { sqliteTable, text, integer, uniqueIndex } from 'drizzle-orm/sqlite-core';
import { randomUUID } from 'crypto';

export const users = sqliteTable('users', {
  id: text('id').primaryKey().$defaultFn(() => randomUUID()),
  username: text('username').notNull().unique(),
  displayName: text('displayName').notNull(),
  passwordHash: text('passwordHash').notNull(),
  isAdmin: integer('isAdmin').notNull().default(0),
  createdAt: text('createdAt').notNull().$defaultFn(() => new Date().toISOString()),
});

export const refreshTokens = sqliteTable('refresh_tokens', {
  id: text('id').primaryKey().$defaultFn(() => randomUUID()),
  userId: text('userId').notNull().references(() => users.id, { onDelete: 'cascade' }),
  token_hash: text('token_hash').notNull().unique(),
  expiresAt: text('expiresAt').notNull(),
  createdAt: text('createdAt').notNull().$defaultFn(() => new Date().toISOString()),
});

export const playlists = sqliteTable('playlists', {
  id: text('id').primaryKey().$defaultFn(() => randomUUID()),
  userId: text('userId').notNull().references(() => users.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  createdAt: text('createdAt').notNull().$defaultFn(() => new Date().toISOString()),
  updatedAt: text('updatedAt').notNull().$defaultFn(() => new Date().toISOString()),
});

export const playlistTracks = sqliteTable(
  'playlist_tracks',
  {
    id: text('id').primaryKey().$defaultFn(() => randomUUID()),
    playlistId: text('playlistId').notNull().references(() => playlists.id, { onDelete: 'cascade' }),
    lidarrTrackId: integer('lidarrTrackId').notNull(),
    position: integer('position').notNull(),
  },
  (table) => ({
    uniquePlaylistTrack: uniqueIndex('playlist_tracks_playlistId_lidarrTrackId_idx').on(
      table.playlistId,
      table.lidarrTrackId,
    ),
  }),
);

export const offlineTracks = sqliteTable(
  'offline_tracks',
  {
    id: text('id').primaryKey().$defaultFn(() => randomUUID()),
    userId: text('userId').notNull().references(() => users.id, { onDelete: 'cascade' }),
    lidarrTrackId: integer('lidarrTrackId').notNull(),
    deviceId: text('deviceId').notNull(),
    bitrate: integer('bitrate').notNull().default(320),
    filePath: text('filePath'),
    fileSize: integer('fileSize'),
    status: text('status').notNull().default('pending'),
    requestedAt: text('requestedAt').notNull().$defaultFn(() => new Date().toISOString()),
    completedAt: text('completedAt'),
  },
  (table) => ({
    uniqueUserTrackDevice: uniqueIndex('offline_tracks_userId_trackId_deviceId_idx').on(
      table.userId,
      table.lidarrTrackId,
      table.deviceId,
    ),
  }),
);

export const requests = sqliteTable('requests', {
  id: text('id').primaryKey().$defaultFn(() => randomUUID()),
  userId: text('userId').notNull().references(() => users.id, { onDelete: 'cascade' }),
  type: text('type').notNull(),
  lidarrId: integer('lidarrId').notNull(),
  status: text('status').notNull().default('pending'),
  requestedAt: text('requestedAt').notNull().$defaultFn(() => new Date().toISOString()),
  resolvedAt: text('resolvedAt'),
});

export const schema = {
  users,
  refreshTokens,
  playlists,
  playlistTracks,
  offlineTracks,
  requests,
};
