import '../config.dart';
import 'messagepack.dart';
import 'protobuf_decoder.dart';

/// The decoders every inspector has, which the viewer asks after the ones the
/// app registered. Neither needs a schema: MessagePack describes itself, and a
/// Protobuf body with none is shown by field number.
const List<FlutwireBodyDecoder> builtInDecoders = [
  FlutwireMessagePackDecoder(),
  FlutwireProtobufDecoder.raw(),
];
