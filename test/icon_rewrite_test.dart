import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
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
}
