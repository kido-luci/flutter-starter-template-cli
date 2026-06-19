import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('isPngPath', () {
    test('accepts .png regardless of case or directory', () {
      expect(isPngPath('icon.png'), isTrue);
      expect(isPngPath('ICON.PNG'), isTrue);
      expect(isPngPath('assets/brand/app_icon.png'), isTrue);
    });

    test('rejects non-png and extension-less paths', () {
      expect(isPngPath('icon.jpg'), isFalse);
      expect(isPngPath('icon.svg'), isFalse);
      expect(isPngPath('icon'), isFalse);
      expect(isPngPath(''), isFalse);
    });
  });

  group('installLauncherIcon', () {
    test('copies the source PNG to app_icon and the adaptive foreground', () {
      final dir = Directory.systemTemp.createTempSync('fst_icon_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = File(p.join(dir.path, 'source.png'))
        ..writeAsBytesSync([1, 2, 3, 4]);

      installLauncherIcon(dir.path, source.path);

      final iconsDir = p.join(dir.path, 'tool', 'launcher_icons');
      final icon = File(p.join(iconsDir, 'app_icon.png'));
      final foreground = File(p.join(iconsDir, 'app_icon_foreground.png'));
      expect(icon.existsSync(), isTrue);
      expect(foreground.existsSync(), isTrue);
      expect(icon.readAsBytesSync(), equals([1, 2, 3, 4]));
      expect(foreground.readAsBytesSync(), equals([1, 2, 3, 4]));
    });
  });
}
