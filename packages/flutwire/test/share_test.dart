import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/platform/native.dart';
import 'package:flutwire/src/share.dart';

import 'ui/calls.dart';

const _channel = MethodChannel('flutwire.test/share');

/// A store that hands out the full call, as one kept on disk does.
class _FullStore extends MemoryFlutwireStore {
  _FullStore(this.full);

  final FlutwireCall full;

  @override
  Future<FlutwireCall?> load(int id) async => id == full.id ? full : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory folder;
  late List<MethodCall> shared;
  late bool sheetAvailable;
  String? clipboard;

  FlutwireSharing sharing({String? path, FlutwireStore? store}) =>
      FlutwireSharing(
        native: FlutwireNative(channel: _channel),
        store: store ?? MemoryFlutwireStore(),
        temporaryPath: path,
        version: '1.2.3',
      );

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('flutwire_share_');
    shared = [];
    sheetAvailable = true;
    clipboard = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      shared.add(call);
      return sheetAvailable;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  group('render', () {
    test('writes the calls in the format asked for', () async {
      final text = await sharing().render([
        makeCall(1),
      ], FlutwireExportFormat.curl);

      expect(text, contains("curl 'https://api.test/items'"));
    });

    test('reads each call back with its bodies first', () async {
      final summary = makeCall(1);
      final full = makeCall(1, responseBody: '{"club":"Orion"}');

      final text = await sharing(
        store: _FullStore(full),
      ).render([summary], FlutwireExportFormat.json);

      expect(text, contains('Orion'));
    });

    test('puts the version in a HAR file', () async {
      final text = await sharing().render([
        makeCall(1),
      ], FlutwireExportFormat.har);

      expect(text, contains('1.2.3'));
    });
  });

  group('share', () {
    test('hands a short text to the sheet as text', () async {
      final done = await sharing().share(
        [makeCall(1)],
        FlutwireExportFormat.text,
        subject: 'GET api.test/items',
      );

      expect(done, isTrue);
      expect(shared.single.method, 'share');
      final arguments = shared.single.arguments as Map;
      expect(arguments['text'], contains('/items'));
      expect(arguments['filePath'], isNull);
      expect(arguments['subject'], 'GET api.test/items');
    });

    test('copies the text when there is no sheet', () async {
      sheetAvailable = false;

      final done = await sharing().share(
        [makeCall(1)],
        FlutwireExportFormat.text,
        subject: 's',
      );

      expect(done, isFalse);
      expect(clipboard, contains('/items'));
    });

    test('hands a HAR file to the sheet as a file', () async {
      final done = await sharing(path: folder.path).share(
        [makeCall(1)],
        FlutwireExportFormat.har,
        subject: 'GET api.test/items',
      );

      expect(done, isTrue);
      final arguments = shared.single.arguments as Map;
      final file = File(arguments['filePath']! as String);
      expect(file.path, startsWith(folder.path));
      expect(file.path, endsWith('.har'));
      expect(arguments['mimeType'], 'application/json');
      expect(await file.readAsString(), contains('"log"'));
    });

    test('sends a text that is too long as a file as well', () async {
      final big = makeCall(1, url: 'https://api.test/${'a' * 70000}');

      await sharing(
        path: folder.path,
      ).share([big], FlutwireExportFormat.text, subject: 's');

      final arguments = shared.single.arguments as Map;
      expect(arguments['text'], isNull);
      expect(arguments['filePath'] as String, endsWith('.txt'));
    });

    test('copies a file format when there is nowhere to write it', () async {
      final done = await sharing().share(
        [makeCall(1)],
        FlutwireExportFormat.json,
        subject: 's',
      );

      expect(done, isFalse);
      expect(shared, isEmpty);
      expect(clipboard, contains('"calls"'));
    });
  });

  group('shareBytes and shareText', () {
    test('write the file and name it in the subject', () async {
      final done = await sharing(path: folder.path).shareBytes(
        Uint8List.fromList([1, 2, 3]),
        'body.bin',
        'application/octet-stream',
      );

      expect(done, isTrue);
      final arguments = shared.single.arguments as Map;
      expect(arguments['subject'], 'body.bin');
      expect(arguments['mimeType'], 'application/octet-stream');
      expect(await File('${folder.path}/body.bin').readAsBytes(), [1, 2, 3]);
    });

    test('share text as a plain text file', () async {
      final done = await sharing(
        path: folder.path,
      ).shareText('hello', 'note.txt');

      expect(done, isTrue);
      expect((shared.single.arguments as Map)['mimeType'], 'text/plain');
      expect(await File('${folder.path}/note.txt').readAsString(), 'hello');
    });

    test('say no when there is nowhere to write', () async {
      final bytes = await sharing().shareBytes(Uint8List(1), 'a', 'b');
      final text = await sharing().shareText('x', 'a.txt');

      expect(bytes, isFalse);
      expect(text, isFalse);
      expect(shared, isEmpty);
    });

    test('say no when there is no sheet to hand the file to', () async {
      sheetAvailable = false;

      final done = await sharing(path: folder.path).shareText('x', 'a.txt');

      expect(done, isFalse);
    });
  });
}
