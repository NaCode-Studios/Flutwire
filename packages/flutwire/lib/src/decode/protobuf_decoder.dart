import 'dart:convert';
import 'dart:typed_data';

import '../config.dart';
import '../model/body.dart';
import '../model/call.dart';
import 'decoded_text.dart';
import 'protobuf/schema.dart';
import 'protobuf/values.dart';

/// Shows a Protobuf body as indented text that reads like JSON.
///
/// With a descriptor set the fields come out by name, typed, with enums by name,
/// maps as objects and packed runs as lists. Without one they come out by field
/// number, guessed the way `protoc --decode_raw` guesses. Inspector builds
/// register the schema-less one for you, after the decoders you list.
///
/// The decoder answers for bodies whose media type says Protobuf
/// (`application/x-protobuf`, `application/protobuf` and
/// `application/vnd.google.protobuf`) and for gRPC and gRPC-web
/// (`application/grpc`, `application/grpc-web`, with or without `+proto`),
/// whose messages come in frames. It passes on anything it cannot read to the
/// end, or that was cut.
///
/// The decoder runs when a body is shown, so the capture is not touched.
final class FlutwireProtobufDecoder implements FlutwireBodyDecoder {
  /// Creates a decoder that reads messages with the types in [descriptorSet],
  /// the bytes of a `FileDescriptorSet` that `protoc --descriptor_set_out` with
  /// `--include_imports` writes. Throws a [FormatException] when they are not
  /// one.
  ///
  /// A gRPC call finds its message types by itself, from the method in its
  /// address. For any other Protobuf body [messageType] says which message it
  /// is, by full name such as `demo.Person`, and a body it has no answer for is
  /// read by field number.
  FlutwireProtobufDecoder({required List<int> descriptorSet, this.messageType})
    : _schema = ProtoSchema.fromDescriptorSet(descriptorSet);

  /// Creates a decoder with no schema, which shows fields by number.
  const FlutwireProtobufDecoder.raw() : _schema = null, messageType = null;

  final ProtoSchema? _schema;

  /// Names the message a Protobuf body that is not gRPC holds, by full name, or
  /// null when it does not know.
  final String? Function(FlutwireCall call, {required bool isRequest})?
  messageType;

  @override
  String get name => _schema == null ? 'Protobuf (no schema)' : 'Protobuf';

  @override
  String? decode(
    FlutwireCall call,
    FlutwireBody body, {
    required bool isRequest,
  }) {
    if (!body.loaded || body.isEmpty || body.truncated) return null;
    final mime = body.mimeType;
    if (mime == null) return null;
    final grpc = _isGrpc(mime);
    if (!grpc && !_isProtobuf(mime)) return null;
    final values = ProtoValues(_schema);
    final type = _typeFor(call, isRequest, grpc);
    try {
      return renderDecoded(
        grpc
            ? _frames(body.bytes, values, type)
            : values.message(body.bytes, type),
      );
    } on FormatException {
      return null;
    }
  }

  ProtoMessage? _typeFor(FlutwireCall call, bool isRequest, bool grpc) {
    final schema = _schema;
    if (schema == null) return null;
    if (grpc) {
      final method = schema.methodAt(call.uri.path);
      if (method == null) return null;
      return schema.message(isRequest ? method.inputType : method.outputType);
    }
    final name = messageType?.call(call, isRequest: isRequest);
    return name == null ? null : schema.message(name);
  }

  /// The messages of a gRPC body, each behind a flag byte and a length, and the
  /// trailers a gRPC-web response ends with.
  static Object? _frames(
    Uint8List bytes,
    ProtoValues values,
    ProtoMessage? type,
  ) {
    final frames = <Object?>[];
    var at = 0;
    while (at < bytes.length) {
      if (bytes.length - at < 5) throw const FormatException('cut short');
      final flag = bytes[at];
      final length = ByteData.sublistView(bytes, at + 1, at + 5).getUint32(0);
      at += 5;
      if (length > bytes.length - at) throw const FormatException('cut short');
      final payload = Uint8List.sublistView(bytes, at, at + length);
      at += length;
      if ((flag & 0x80) != 0) {
        frames.add({'trailers': _trailers(payload)});
      } else if ((flag & 0x01) != 0) {
        // The algorithm is named in a header, and the decoder has none to run.
        frames.add({
          'compressed': true,
          'bytes': DecodedBytes(Uint8List.fromList(payload)),
        });
      } else {
        frames.add(values.message(payload, type));
      }
    }
    return frames.length == 1 ? frames.single : frames;
  }

  static Map<String, Object?> _trailers(Uint8List payload) {
    final trailers = <String, Object?>{};
    for (final line in const LineSplitter().convert(
      utf8.decode(payload, allowMalformed: true),
    )) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      trailers[line.substring(0, colon).trim()] = line
          .substring(colon + 1)
          .trim();
    }
    return trailers;
  }

  static bool _isGrpc(String mime) =>
      mime == 'application/grpc' ||
      mime == 'application/grpc+proto' ||
      mime == 'application/grpc-web' ||
      mime == 'application/grpc-web+proto';

  static bool _isProtobuf(String mime) =>
      mime == 'application/x-protobuf' ||
      mime == 'application/protobuf' ||
      mime == 'application/vnd.google.protobuf' ||
      mime == 'application/x-google-protobuf';
}
