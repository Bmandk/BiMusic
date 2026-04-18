import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/update_info.dart';

void main() {
  group('SemVer.tryParse', () {
    test('parses app-v1.2.3+42 format', () {
      final v = SemVer.tryParse('app-v1.2.3+42');
      expect(v, const SemVer(1, 2, 3));
    });

    test('parses v1.2.3 format', () {
      expect(SemVer.tryParse('v1.2.3'), const SemVer(1, 2, 3));
    });

    test('parses bare 1.2.3 format', () {
      expect(SemVer.tryParse('1.2.3'), const SemVer(1, 2, 3));
    });

    test('parses app-v1.0.0 without build number', () {
      expect(SemVer.tryParse('app-v1.0.0'), const SemVer(1, 0, 0));
    });

    test('returns null for garbage input', () {
      expect(SemVer.tryParse('garbage'), isNull);
    });

    test('returns null for empty string', () {
      expect(SemVer.tryParse(''), isNull);
    });

    test('handles pre-release suffix by ignoring it', () {
      expect(SemVer.tryParse('1.0.0-beta'), const SemVer(1, 0, 0));
    });
  });

  group('SemVer comparison', () {
    test('equal versions are not greater', () {
      expect(const SemVer(1, 0, 0) > const SemVer(1, 0, 0), isFalse);
    });

    test('higher major is greater', () {
      expect(const SemVer(2, 0, 0) > const SemVer(1, 9, 9), isTrue);
    });

    test('higher minor is greater when major equal', () {
      expect(const SemVer(1, 1, 0) > const SemVer(1, 0, 9), isTrue);
    });

    test('higher patch is greater when major and minor equal', () {
      expect(const SemVer(1, 0, 1) > const SemVer(1, 0, 0), isTrue);
    });

    test('lower version is not greater', () {
      expect(const SemVer(1, 0, 0) > const SemVer(2, 0, 0), isFalse);
    });

    test('equality holds', () {
      expect(const SemVer(1, 2, 3), equals(const SemVer(1, 2, 3)));
    });

    test('toString returns dotted form', () {
      expect(const SemVer(1, 2, 3).toString(), '1.2.3');
    });
  });

  group('UpdateInfo.fromGitHubRelease', () {
    const currentVersion = SemVer(1, 0, 0);

    Map<String, dynamic> release({
      String tagName = 'app-v1.1.0+10',
      String? body,
      String? htmlUrl,
      List<Map<String, dynamic>> assets = const [],
    }) =>
        {
          'tag_name': tagName,
          'body': body ?? 'Release notes',
          'html_url': htmlUrl ?? 'https://github.com/Bmandk/BiMusic/releases/tag/$tagName',
          'assets': assets,
        };

    test('updateAvailable is true when latest > current', () {
      final info = UpdateInfo.fromGitHubRelease(
        release(tagName: 'app-v1.1.0+10'),
        currentVersion,
      );
      expect(info.updateAvailable, isTrue);
      expect(info.latestVersion, const SemVer(1, 1, 0));
    });

    test('updateAvailable is false when latest == current', () {
      final info = UpdateInfo.fromGitHubRelease(
        release(tagName: 'app-v1.0.0+5'),
        currentVersion,
      );
      expect(info.updateAvailable, isFalse);
    });

    test('updateAvailable is false when latest < current', () {
      final info = UpdateInfo.fromGitHubRelease(
        release(tagName: 'app-v0.9.0+1'),
        currentVersion,
      );
      expect(info.updateAvailable, isFalse);
    });

    test('picks APK asset by name', () {
      final info = UpdateInfo.fromGitHubRelease(
        release(assets: [
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://example.com/app-release.apk',
            'size': 12345678,
          },
        ]),
        currentVersion,
      );
      expect(info.apkAssetUrl, 'https://example.com/app-release.apk');
      expect(info.apkAssetSize, 12345678);
    });

    test('picks Windows ZIP asset by name', () {
      final info = UpdateInfo.fromGitHubRelease(
        release(assets: [
          {
            'name': 'bimusic_app-windows-x64.zip',
            'browser_download_url': 'https://example.com/bimusic.zip',
            'size': 99000000,
          },
        ]),
        currentVersion,
      );
      expect(info.windowsAssetUrl, 'https://example.com/bimusic.zip');
      expect(info.windowsAssetSize, 99000000);
    });

    test('unknown asset names are ignored', () {
      final info = UpdateInfo.fromGitHubRelease(
        release(assets: [
          {
            'name': 'source.tar.gz',
            'browser_download_url': 'https://example.com/source.tar.gz',
            'size': 1000,
          },
        ]),
        currentVersion,
      );
      expect(info.apkAssetUrl, isNull);
      expect(info.windowsAssetUrl, isNull);
    });

    test('handles missing assets list gracefully', () {
      final payload = <String, dynamic>{
        'tag_name': 'app-v1.1.0',
        'body': 'notes',
        'html_url': 'https://example.com',
      };
      final info = UpdateInfo.fromGitHubRelease(payload, currentVersion);
      expect(info.apkAssetUrl, isNull);
      expect(info.windowsAssetUrl, isNull);
    });

    test('stores currentVersion and releaseNotes', () {
      final info = UpdateInfo.fromGitHubRelease(
        release(body: 'Fixed a bug'),
        currentVersion,
      );
      expect(info.currentVersion, currentVersion);
      expect(info.releaseNotes, 'Fixed a bug');
    });
  });
}
