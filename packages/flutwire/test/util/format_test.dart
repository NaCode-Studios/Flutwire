import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/util/format.dart';

void main() {
  group('formatBytes', () {
    test('counts small sizes in bytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('steps up a unit every 1024', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
      expect(formatBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
    });

    test('drops the decimal from 100 up', () {
      expect(formatBytes(150 * 1024), '150 KB');
    });

    test('stops at terabytes', () {
      expect(formatBytes(2048 * 1024 * 1024 * 1024 * 1024), '2048 TB');
    });
  });

  group('formatDuration', () {
    test('uses milliseconds under a second', () {
      expect(formatDuration(const Duration(milliseconds: 85)), '85 ms');
    });

    test('uses seconds under a minute', () {
      expect(formatDuration(const Duration(milliseconds: 1240)), '1.24 s');
    });

    test('uses minutes and seconds after that', () {
      expect(formatDuration(const Duration(seconds: 125)), '2 min 5 s');
    });
  });

  group('reasonPhraseFor', () {
    test('knows the common statuses', () {
      expect(reasonPhraseFor(200), 'OK');
      expect(reasonPhraseFor(404), 'Not Found');
      expect(reasonPhraseFor(503), 'Service Unavailable');
    });

    test('is empty for a status it does not know', () {
      expect(reasonPhraseFor(599), '');
    });
  });

  group('formatAgo', () {
    final now = DateTime.utc(2026, 10, 23, 12);

    test('says now for the last moments', () {
      expect(formatAgo(now.subtract(const Duration(seconds: 2)), now), 'now');
    });

    test('counts seconds, minutes and hours', () {
      expect(formatAgo(now.subtract(const Duration(seconds: 12)), now), '12s');
      expect(formatAgo(now.subtract(const Duration(minutes: 4)), now), '4m');
      expect(formatAgo(now.subtract(const Duration(hours: 3)), now), '3h');
    });

    test('gives the date from a day on', () {
      final text = formatAgo(now.subtract(const Duration(days: 2)), now);

      expect(text, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });

  group('formatClock and formatDateTime', () {
    final time = DateTime(2026, 10, 3, 4, 5, 6, 7);

    test('pad every part', () {
      expect(formatClock(time), '04:05:06.007');
      expect(formatDateTime(time), '2026-10-03 04:05:06.007');
    });
  });
}
