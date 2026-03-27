BiMusic will be a music streaming software that is integrated with Lidarr. The app will be crossplatform to work for mobile, web, and desktop. It's primary features are the following:

* Allow multiple users to login and all have access to the music on the server
* Stream and play music
* Make songs available for offline use when requested (individual for each user's device)
* Search and request new music via Lidarr's API
* Organize music into playlists

The app should have a simple backend using Node.js, TypeScript, and running in an LXC to facilitate logging in, and streaming/transcoding via ffmpeg. It should also facilitate interaction with Lidarr so the frontend only needs to authenticate and communicate with one backend, but this should be a simple layer. Scale is *not* a concern as this will only be used by a few users. 

The client should be built using Flutter to allow easy cross platform deployment and similar UI, although the layouts should be different to accomodate the affordances of each platform without being too different. The user should generally be trusted to manage their storage, but it should be easily accessible how much storage is currently in use. Use 320k bitrate for streaming when on WiFi and 5G, and 128k bitrate for lower quality service. Albums and playlists can be marked as available offline as well, which will download songs in the background at 320k bitrate. 

Authentication should work using JWT with a refresh token. The API should generally use REST for communication. The backend and frontend should both have simple logging to file on disk. 

Both frontend and backend should have test coverage to ensure that changes does not break anything, and that integration between the backend and frontend keeps working, which should run on CI in GitHub Actions. 