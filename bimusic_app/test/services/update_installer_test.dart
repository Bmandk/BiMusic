import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/services/update_installer.dart';

void main() {
  group('WindowsUpdateInstaller.buildPowerShellScriptBody', () {
    test('script contains param block with expected parameters', () {
      final body = WindowsUpdateInstaller.buildPowerShellScriptBody();
      expect(body, contains('ParentPid'));
      expect(body, contains('ZipPath'));
      expect(body, contains('InstallDir'));
      expect(body, contains('ExeName'));
    });

    test('script waits for parent process to exit', () {
      final body = WindowsUpdateInstaller.buildPowerShellScriptBody();
      expect(body, contains('Get-Process'));
      expect(body, contains('ParentPid'));
    });

    test('script extracts zip to a staging directory', () {
      final body = WindowsUpdateInstaller.buildPowerShellScriptBody();
      expect(body, contains('Expand-Archive'));
    });

    test('script copies staged files to install dir', () {
      final body = WindowsUpdateInstaller.buildPowerShellScriptBody();
      expect(body, contains('Copy-Item'));
      expect(body, contains('InstallDir'));
    });

    test('script relaunches the exe', () {
      final body = WindowsUpdateInstaller.buildPowerShellScriptBody();
      expect(body, contains('Start-Process'));
      expect(body, contains('ExeName'));
    });

    test('script cleans up zip and staging on completion', () {
      final body = WindowsUpdateInstaller.buildPowerShellScriptBody();
      expect(body, contains('Remove-Item'));
      expect(body, contains('ZipPath'));
    });

    test('script logs errors rather than silently swallowing them', () {
      final body = WindowsUpdateInstaller.buildPowerShellScriptBody();
      expect(body, contains('catch'));
      expect(body, contains('Out-File'));
    });
  });
}
