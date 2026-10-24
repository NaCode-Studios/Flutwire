import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';

FlutwireCall call({int? resentFrom}) => FlutwireCall(
  id: 20,
  method: 'POST',
  uri: Uri.parse('https://api.test/items'),
  source: FlutwireSource.io,
  startedAt: DateTime.utc(2026, 10, 24, 12),
  request: FlutwireRequest(
    headers: FlutwireHeaders.empty,
    body: FlutwireBody.empty(),
  ),
  resentFrom: resentFrom,
);

void main() {
  group('a call that repeats another', () {
    test('names it in its summary and reads it back', () {
      final json = call(resentFrom: 12).toJson();

      expect(json['resentFrom'], 12);
      expect(FlutwireCall.fromJson(json).resentFrom, 12);
    });

    test('keeps the link when it changes', () {
      final changed = call(resentFrom: 12).copyWith(pinned: true);

      expect(changed.resentFrom, 12);
    });

    test('leaves the summary of an ordinary call as it was', () {
      final json = call().toJson();

      expect(json.containsKey('resentFrom'), isFalse);
      expect(FlutwireCall.fromJson(json).resentFrom, isNull);
    });
  });
}
