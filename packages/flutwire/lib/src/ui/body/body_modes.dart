import '../../model/body.dart';

/// One way of showing a body.
enum BodyMode {
  /// What an app-supplied decoder made of the body.
  decoded,

  /// A JSON document as a tree.
  tree,

  /// The body indented for reading.
  pretty,

  /// The text exactly as it was sent.
  raw,

  /// The bytes as a hex dump.
  hex,

  /// A form as a list of fields.
  fields,

  /// A multipart upload as a stack of cards.
  parts,

  /// An image, drawn.
  preview;

  /// Whether the mode shows text the search can look through.
  bool get isSearchable => this != hex && this != preview;

  /// Whether the mode shows text as code, with line numbers and wrapping.
  bool get isCode => this == decoded || this == pretty || this == raw;
}

/// The modes a body is shown in, and the one it opens in.
///
/// It depends on nothing but the body and on whether a decoder recognised it,
/// so the viewer only has to ask.
final class BodyModes {
  /// Works out the modes of [body]. [hasDecoded] says that a decoder produced
  /// text for it, which adds [BodyMode.decoded] in front and makes it the
  /// first thing shown.
  BodyModes(this.body, {required this.hasDecoded});

  /// The body the modes are for.
  final FlutwireBody body;

  /// Whether a decoder recognised the body.
  final bool hasDecoded;

  /// Every mode on offer, in the order the toolbar lists them.
  late final List<BodyMode> all = [if (hasDecoded) BodyMode.decoded, ..._own];

  /// The mode the body opens in.
  BodyMode get initial => hasDecoded ? BodyMode.decoded : undecoded;

  /// The mode that shows the body itself, ignoring any decoder.
  BodyMode get undecoded {
    if (_own.isEmpty) return BodyMode.raw;
    if (body.kind == FlutwireBodyKind.json) {
      return body.isValidJson ? BodyMode.tree : BodyMode.raw;
    }
    return _own.first;
  }

  /// Whether [mode] can be picked. A cut or malformed JSON body has no tree and
  /// no indented form.
  bool isEnabled(BodyMode mode) =>
      body.kind != FlutwireBodyKind.json ||
      (mode != BodyMode.tree && mode != BodyMode.pretty) ||
      body.isValidJson;

  List<BodyMode> get _own => switch (body.kind) {
    FlutwireBodyKind.json => const [
      BodyMode.tree,
      BodyMode.pretty,
      BodyMode.raw,
    ],
    FlutwireBodyKind.xml => const [BodyMode.pretty, BodyMode.raw],
    FlutwireBodyKind.html || FlutwireBodyKind.text => const [BodyMode.raw],
    FlutwireBodyKind.form => const [BodyMode.fields, BodyMode.raw],
    FlutwireBodyKind.multipart => const [BodyMode.parts, BodyMode.hex],
    FlutwireBodyKind.image => const [BodyMode.preview, BodyMode.hex],
    FlutwireBodyKind.binary => const [BodyMode.hex],
    FlutwireBodyKind.empty => const [],
  };
}
