import '../model/body.dart';
import '../model/call.dart';
import '../model/multipart.dart';
import '../util/format.dart';

/// Header fields curl sets by itself, and that would only fight it.
const Set<String> _managedByCurl = {
  'host',
  'content-length',
  'connection',
  'transfer-encoding',
  'expect',
  'accept-encoding',
};

/// A shell command that repeats [call].
///
/// The command uses the request as it was recorded, so a value the redaction
/// policy hid appears as the mask for the reader to fill in. A body that was
/// cut, or that is binary, cannot be reproduced; the command says so in a
/// comment above it instead of silently sending something different.
String toCurl(FlutwireCall call, {bool multiline = true}) {
  final notes = <String>[];
  final args = <String>[];
  final request = call.request;
  final body = request.body;
  final method = call.wireMethod;

  // The method and the URL stay together on the first line.
  final target = _quote(call.uri.toString());
  final first = method == 'HEAD'
      ? '--head $target'
      : method == 'GET'
      ? target
      : '-X $method $target';

  if (call.source == FlutwireSource.functions) {
    notes.add(
      'A callable function. The Firebase SDK also sends the signed-in user\'s '
      'ID token and the App Check token, which are not part of this command.',
    );
  }

  final isMultipart = body.kind == FlutwireBodyKind.multipart;
  for (final field in request.headers.entries) {
    final name = field.key.toLowerCase();
    if (_managedByCurl.contains(name)) continue;
    // curl writes its own boundary, so the recorded one would be wrong.
    if (isMultipart && name == 'content-type') continue;
    args.add('-H ${_quote('${field.key}: ${field.value}')}');
  }

  if (body.loaded && !body.isEmpty) {
    if (body.truncated) {
      notes.add(
        'The request body was cut at ${formatBytes(body.bytes.length)} of '
        '${formatBytes(body.totalBytes)}; the command sends only what was kept.',
      );
    }
    if (isMultipart) {
      for (final part in parseMultipart(body)) {
        final name = part.name ?? 'field';
        if (part.isFile) {
          args.add('-F ${_quote('$name=@${part.filename}')}');
          notes.add(
            'Upload ${part.filename} (${formatBytes(part.bytes.length)}) '
            'from disk: its content is not part of the command.',
          );
        } else {
          args.add('-F ${_quote('$name=${part.text ?? ''}')}');
        }
      }
    } else if (body.text != null) {
      args.add('--data-raw ${_quote(body.text!)}');
    } else {
      notes.add(
        'The request body is binary (${formatBytes(body.totalBytes)}) and is '
        'not included.',
      );
    }
  } else if (!body.loaded && body.totalBytes > 0) {
    notes.add('The request body was not loaded and is not included.');
  }

  final accepts = request.headers.first('accept-encoding')?.toLowerCase();
  if (accepts != null &&
      (accepts.contains('gzip') ||
          accepts.contains('deflate') ||
          accepts.contains('br'))) {
    args.add('--compressed');
  }

  final buffer = StringBuffer();
  for (final note in notes) {
    buffer.writeln('# $note');
  }
  buffer.write('curl $first');
  for (final arg in args) {
    buffer.write(multiline ? ' \\\n  $arg' : ' $arg');
  }
  return buffer.toString();
}

String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
