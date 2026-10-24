import 'dart:typed_data';

const _mask = [0x12, 0x34, 0x56, 0x78];

/// One frame as it goes over the wire.
Uint8List frame(
  int opcode,
  List<int> payload, {
  bool fin = true,
  bool masked = false,
  bool rsv1 = false,
}) {
  final out = BytesBuilder();
  out.addByte((fin ? 0x80 : 0) | (rsv1 ? 0x40 : 0) | opcode);
  final maskBit = masked ? 0x80 : 0;
  if (payload.length < 126) {
    out.addByte(maskBit | payload.length);
  } else if (payload.length < 65536) {
    out.addByte(maskBit | 126);
    out.add([payload.length >> 8, payload.length & 0xff]);
  } else {
    out.addByte(maskBit | 127);
    out.add([
      for (var shift = 56; shift >= 0; shift -= 8)
        (payload.length >> shift) & 0xff,
    ]);
  }
  if (masked) {
    out.add(_mask);
    out.add([
      for (var i = 0; i < payload.length; i++) payload[i] ^ _mask[i & 3],
    ]);
  } else {
    out.add(payload);
  }
  return out.toBytes();
}
