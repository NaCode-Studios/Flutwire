import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';

bool _active(FlutwireConfig config, {required String mode}) =>
    config.activeIn(release: mode == 'release', debug: mode == 'debug');

void main() {
  group('when it records', () {
    test('by default in a debug build only', () {
      const config = FlutwireConfig();

      expect(_active(config, mode: 'debug'), isTrue);
      expect(_active(config, mode: 'profile'), isFalse);
      expect(_active(config, mode: 'release'), isFalse);
    });

    test('never in a release build, whatever enabled says', () {
      const config = FlutwireConfig(enabled: true);

      expect(_active(config, mode: 'release'), isFalse);
    });

    test('in a release build only when that is allowed', () {
      expect(
        _active(const FlutwireConfig(allowInRelease: true), mode: 'release'),
        isTrue,
      );
      expect(
        _active(
          const FlutwireConfig(allowInRelease: true, enabled: false),
          mode: 'release',
        ),
        isFalse,
      );
    });

    test('enabled switches a debug or profile build on or off', () {
      const on = FlutwireConfig(enabled: true);
      const off = FlutwireConfig(enabled: false);

      expect(_active(on, mode: 'profile'), isTrue);
      expect(_active(on, mode: 'debug'), isTrue);
      expect(_active(off, mode: 'debug'), isFalse);
    });

    test('follows the build running the tests', () {
      expect(const FlutwireConfig().isActive, isTrue);
      expect(const FlutwireConfig(enabled: false).isActive, isFalse);
    });
  });
}
