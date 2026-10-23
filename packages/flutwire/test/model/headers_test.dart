import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/model/headers.dart';

void main() {
  group('FlutwireHeaders', () {
    final headers = FlutwireHeaders([
      const MapEntry('Content-Type', 'application/json; charset=utf-8'),
      const MapEntry('Set-Cookie', 'a=1'),
      const MapEntry('set-cookie', 'b=2'),
      const MapEntry('Content-Length', ' 42 '),
    ]);

    test('looks names up without regard to case', () {
      expect(headers['CONTENT-TYPE'], ['application/json; charset=utf-8']);
      expect(headers.first('content-type'), 'application/json; charset=utf-8');
      expect(headers.contains('SET-COOKIE'), isTrue);
      expect(headers.contains('x-missing'), isFalse);
    });

    test('keeps repeated fields and the first spelling of a name', () {
      expect(headers['set-cookie'], ['a=1', 'b=2']);
      expect(headers.names, ['Content-Type', 'Set-Cookie', 'Content-Length']);
      expect(headers.length, 3);
    });

    test('walks every value in the order it was recorded', () {
      expect(headers.entries.map((e) => '${e.key}=${e.value}'), [
        'Content-Type=application/json; charset=utf-8',
        'Set-Cookie=a=1',
        'Set-Cookie=b=2',
        'Content-Length= 42 ',
      ]);
    });

    test('reads the well-known fields', () {
      expect(headers.contentType, startsWith('application/json'));
      expect(headers.contentLength, 42);
      expect(headers.contentEncoding, isNull);
      expect(
        FlutwireHeaders.fromMap({'Content-Encoding': 'GZIP'}).contentEncoding,
        'gzip',
      );
    });

    test('treats a malformed Content-Length as absent', () {
      expect(
        FlutwireHeaders.fromMap({'content-length': 'abc'}).contentLength,
        isNull,
      );
    });

    test('builds from the map shapes the HTTP clients return', () {
      final fromMap = FlutwireHeaders.fromMap({
        'accept': ['a', 'b'],
        'x-count': 3,
        'x-null': null,
      });
      expect(fromMap['accept'], ['a', 'b']);
      expect(fromMap.first('x-count'), '3');
      expect(fromMap.contains('x-null'), isFalse);
    });

    test('redacts by name and leaves the rest alone', () {
      final redacted = FlutwireHeaders.fromMap({
        'Authorization': 'Bearer secret',
        'Accept': 'application/json',
      }).redact({'authorization'}, mask: '**');
      expect(redacted.first('Authorization'), '**');
      expect(redacted.first('Accept'), 'application/json');
    });

    test('round-trips through JSON', () {
      expect(FlutwireHeaders.fromJson(headers.toJson()), headers);
    });

    test('ignores JSON that is not a list of pairs', () {
      expect(FlutwireHeaders.fromJson('nope'), FlutwireHeaders.empty);
      expect(
        FlutwireHeaders.fromJson([
          1,
          ['only-name'],
        ]),
        FlutwireHeaders.empty,
      );
    });
  });
}
