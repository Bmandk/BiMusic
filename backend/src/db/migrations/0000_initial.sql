CREATE TABLE `users` (
  `id` text PRIMARY KEY NOT NULL,
  `username` text NOT NULL,
  `displayName` text NOT NULL,
  `passwordHash` text NOT NULL,
  `isAdmin` integer DEFAULT 0 NOT NULL,
  `createdAt` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `users_username_unique` ON `users` (`username`);
--> statement-breakpoint
CREATE TABLE `refresh_tokens` (
  `id` text PRIMARY KEY NOT NULL,
  `userId` text NOT NULL,
  `token_hash` text NOT NULL,
  `expiresAt` text NOT NULL,
  `createdAt` text NOT NULL,
  FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `refresh_tokens_token_hash_unique` ON `refresh_tokens` (`token_hash`);
--> statement-breakpoint
CREATE TABLE `playlists` (
  `id` text PRIMARY KEY NOT NULL,
  `userId` text NOT NULL,
  `name` text NOT NULL,
  `createdAt` text NOT NULL,
  `updatedAt` text NOT NULL,
  FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `playlist_tracks` (
  `id` text PRIMARY KEY NOT NULL,
  `playlistId` text NOT NULL,
  `lidarrTrackId` integer NOT NULL,
  `position` integer NOT NULL,
  FOREIGN KEY (`playlistId`) REFERENCES `playlists`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `playlist_tracks_playlistId_lidarrTrackId_idx` ON `playlist_tracks` (`playlistId`, `lidarrTrackId`);
--> statement-breakpoint
CREATE TABLE `offline_tracks` (
  `id` text PRIMARY KEY NOT NULL,
  `userId` text NOT NULL,
  `lidarrTrackId` integer NOT NULL,
  `deviceId` text NOT NULL,
  `filePath` text,
  `fileSize` integer,
  `status` text DEFAULT 'pending' NOT NULL,
  `requestedAt` text NOT NULL,
  `completedAt` text,
  FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `offline_tracks_userId_trackId_deviceId_idx` ON `offline_tracks` (`userId`, `lidarrTrackId`, `deviceId`);
--> statement-breakpoint
CREATE TABLE `requests` (
  `id` text PRIMARY KEY NOT NULL,
  `userId` text NOT NULL,
  `type` text NOT NULL,
  `lidarrId` integer NOT NULL,
  `status` text DEFAULT 'pending' NOT NULL,
  `requestedAt` text NOT NULL,
  `resolvedAt` text,
  FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
