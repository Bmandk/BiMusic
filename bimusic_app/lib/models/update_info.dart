class SemVer {
  final int major;
  final int minor;
  final int patch;

  const SemVer(this.major, this.minor, this.patch);

  static SemVer? tryParse(String s) {
    final m = RegExp(r'v?(\d+)\.(\d+)\.(\d+)').firstMatch(s);
    if (m == null) return null;
    return SemVer(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  int compareTo(SemVer other) {
    if (major != other.major) return major - other.major;
    if (minor != other.minor) return minor - other.minor;
    return patch - other.patch;
  }

  bool operator >(SemVer other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is SemVer &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tagName,
    required this.releaseNotes,
    required this.releaseUrl,
    this.apkAssetUrl,
    this.windowsAssetUrl,
    this.apkAssetSize,
    this.windowsAssetSize,
  });

  final SemVer currentVersion;
  final SemVer latestVersion;
  final String tagName;
  final String releaseNotes;
  final String releaseUrl;
  final String? apkAssetUrl;
  final String? windowsAssetUrl;
  final int? apkAssetSize;
  final int? windowsAssetSize;

  bool get updateAvailable => latestVersion > currentVersion;

  factory UpdateInfo.fromGitHubRelease(
    Map<String, dynamic> json,
    SemVer currentVersion,
  ) {
    final tagName = json['tag_name'] as String? ?? '';
    final latestVersion = SemVer.tryParse(tagName) ?? const SemVer(0, 0, 0);
    final releaseNotes = json['body'] as String? ?? '';
    final releaseUrl = json['html_url'] as String? ?? '';

    String? apkAssetUrl;
    String? windowsAssetUrl;
    int? apkAssetSize;
    int? windowsAssetSize;

    final assets = (json['assets'] as List<dynamic>?) ?? const [];
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      final url = asset['browser_download_url'] as String? ?? '';
      final size = asset['size'] as int?;
      if (name == 'app-release.apk') {
        apkAssetUrl = url;
        apkAssetSize = size;
      } else if (name == 'bimusic_app-windows-x64.zip') {
        windowsAssetUrl = url;
        windowsAssetSize = size;
      }
    }

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      tagName: tagName,
      releaseNotes: releaseNotes,
      releaseUrl: releaseUrl,
      apkAssetUrl: apkAssetUrl,
      windowsAssetUrl: windowsAssetUrl,
      apkAssetSize: apkAssetSize,
      windowsAssetSize: windowsAssetSize,
    );
  }
}
