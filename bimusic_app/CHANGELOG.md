# Changelog

## [1.3.0](https://github.com/Bmandk/BiMusic/compare/bimusic_app-v1.2.0...bimusic_app-v1.3.0) (2026-04-29)


### Features

* **flutter:** CSV playlist import with Lidarr album requests ([#30](https://github.com/Bmandk/BiMusic/issues/30)) ([ab559d5](https://github.com/Bmandk/BiMusic/commit/ab559d50f9ab05138e5859236cc6ad1dd00b65f8))
* **flutter:** Scroll-to-volume on player bar + wider volume slider ([#27](https://github.com/Bmandk/BiMusic/issues/27)) ([75009cd](https://github.com/Bmandk/BiMusic/commit/75009cd6ab98b82af4ef0ddca1b8f18c4c855bb9))
* **flutter:** Spacebar toggles play/pause globally ([#31](https://github.com/Bmandk/BiMusic/issues/31)) ([1808413](https://github.com/Bmandk/BiMusic/commit/1808413a301acbe487ae55b59c502eea9533c864))


### Bug Fixes

* **flutter:** Fix volume not persisting across app launches ([#33](https://github.com/Bmandk/BiMusic/issues/33)) ([b78f144](https://github.com/Bmandk/BiMusic/commit/b78f144e27323922435ae8138d882e2cbcc1bfdf))
* **flutter:** Shrink album art and fix overflow in desktop full player ([#32](https://github.com/Bmandk/BiMusic/issues/32)) ([78ab401](https://github.com/Bmandk/BiMusic/commit/78ab40179fad6213711d4049ca4a6a14236b2742))


### Reverts

* Revert PR [#26](https://github.com/Bmandk/BiMusic/issues/26) (HLS VOD) — return to streaming HTTP ([#34](https://github.com/Bmandk/BiMusic/issues/34)) ([5601977](https://github.com/Bmandk/BiMusic/commit/56019770286dd53e124608d122feeac8d1d5aac9))

## [1.2.0](https://github.com/Bmandk/BiMusic/compare/bimusic_app-v1.1.0...bimusic_app-v1.2.0) (2026-04-23)


### Features

* **flutter:** Add desktop tray and launch-at-startup support ([#18](https://github.com/Bmandk/BiMusic/issues/18)) ([50820c1](https://github.com/Bmandk/BiMusic/commit/50820c1cc21c9188dea20e1ec0316dc9e005e967))
* **hls:** Replace progressive HTTP streaming with HLS VOD ([#26](https://github.com/Bmandk/BiMusic/issues/26)) ([7d958e1](https://github.com/Bmandk/BiMusic/commit/7d958e14fb1f9fe378a7469846e84de4f822aba0))


### Bug Fixes

* **flutter:** Fix mobile nav wrapping, desktop player modal height, and volume persistence ([#20](https://github.com/Bmandk/BiMusic/issues/20)) ([b9db4ac](https://github.com/Bmandk/BiMusic/commit/b9db4acc2fb748dfb53717c9e0b78ac18036a0cf))
* **flutter:** Fix Windows auto-updater copying data/ instead of app files ([#21](https://github.com/Bmandk/BiMusic/issues/21)) ([d482eb5](https://github.com/Bmandk/BiMusic/commit/d482eb5c0baf15d5b9dc04cc08744ed5941fdfac))

## [1.1.0](https://github.com/Bmandk/BiMusic/compare/bimusic_app-v1.0.0...bimusic_app-v1.1.0) (2026-04-19)


### Features

* Configurable backend URL with first-run setup and settings edit ([#6](https://github.com/Bmandk/BiMusic/issues/6)) ([e92a0a0](https://github.com/Bmandk/BiMusic/commit/e92a0a0e85a79dcb1a826c81e59554b5065866ab))
* **flutter:** In-app auto-updater + Android release signing ([#8](https://github.com/Bmandk/BiMusic/issues/8)) ([fb40902](https://github.com/Bmandk/BiMusic/commit/fb4090211f9d8d20fc7d74005611bbe762f1aa31))
* **flutter:** Volume slider for desktop and web player bar ([#2](https://github.com/Bmandk/BiMusic/issues/2)) ([00e52eb](https://github.com/Bmandk/BiMusic/commit/00e52eb7b4f32ae2bb41d57fd51b1188e2534b60))


### Bug Fixes

* **android:** Wire foreground-service types, audio service manifest, and cleartext HTTP config ([#10](https://github.com/Bmandk/BiMusic/issues/10)) ([1c43ba1](https://github.com/Bmandk/BiMusic/commit/1c43ba10b1e76a52f85e9c75877d47290586534c))
* **auth:** Persist login across app restarts; tolerate transient refresh failures ([#13](https://github.com/Bmandk/BiMusic/issues/13)) ([a3100bf](https://github.com/Bmandk/BiMusic/commit/a3100bfe393268b3a67b1aeeba87812e2e85b038))
* **flutter:** Proactively refresh JWT before audio streams expire ([#3](https://github.com/Bmandk/BiMusic/issues/3)) ([4412971](https://github.com/Bmandk/BiMusic/commit/44129716d8681395bafffd244a0b007b443340b9))
* **flutter:** Remove unused Isar dependency to fix Android AGP 8.x build ([#5](https://github.com/Bmandk/BiMusic/issues/5)) ([5700836](https://github.com/Bmandk/BiMusic/commit/570083615ec4a339633cbb9e1d09965d0db46d8c))
