# Changelog

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
