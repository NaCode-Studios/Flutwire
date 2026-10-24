import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../model/body.dart';
import '../../model/call.dart';
import '../../resend.dart';
import '../../util/format.dart';
import '../actions.dart';
import '../detail/call_detail_page.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme/tokens.dart';
import '../widgets/method_chip.dart';

/// The methods the picker offers, besides the one the call used.
const List<String> _methods = [
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
];

/// How the body of the call is offered for editing.
enum _BodyMode {
  /// Text, edited in place. An empty body is text with nothing in it.
  text,

  /// Bytes that are not text, which can only be sent as they were recorded.
  recorded,
}

/// A header field is narrow, and its name is a long word in a monospaced face.
const EdgeInsets _fieldPadding = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 12,
);

class _HeaderRow {
  _HeaderRow(String name, String value)
    : name = TextEditingController(text: name),
      value = TextEditingController(text: value);

  final TextEditingController name;
  final TextEditingController value;

  void dispose() {
    name.dispose();
    value.dispose();
  }
}

/// A recorded call opened for changes, to be sent again.
///
/// It starts as the call was: the same method, address, header fields and body.
/// A value the redaction hid is flagged and not sent, because Flutwire never
/// held it. What is sent is recorded as a new call that names this one.
class ResendPage extends StatefulWidget {
  /// Opens [call], which must have its bodies loaded.
  const ResendPage({super.key, required this.call});

  /// The call to repeat.
  final FlutwireCall call;

  @override
  State<ResendPage> createState() => _ResendPageState();
}

class _ResendPageState extends State<ResendPage> {
  late final TextEditingController _url;
  late final TextEditingController _body;
  late final _BodyMode _mode;
  final List<_HeaderRow> _headers = [];
  late String _method;
  bool _sendRecordedBody = true;
  bool _sending = false;
  bool _triedToSend = false;

  FlutwireBody get _recorded => widget.call.request.body;

  @override
  void initState() {
    super.initState();
    final call = widget.call;
    _method = call.method;
    _url = TextEditingController(text: call.uri.toString())
      ..addListener(_changed);
    _mode = _modeOf(_recorded);
    _body = TextEditingController(
      text: _mode == _BodyMode.text ? _recorded.text ?? '' : '',
    );
    for (final field in call.request.headers.entries) {
      if (clientManagedHeaders.contains(field.key.toLowerCase())) continue;
      _headers.add(_row(field.key, field.value));
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _body.dispose();
    for (final row in _headers) {
      row.dispose();
    }
    super.dispose();
  }

  static _BodyMode _modeOf(FlutwireBody body) {
    if (!body.loaded) return _BodyMode.recorded;
    return switch (body.kind) {
      FlutwireBodyKind.empty ||
      FlutwireBodyKind.json ||
      FlutwireBodyKind.xml ||
      FlutwireBodyKind.html ||
      FlutwireBodyKind.text ||
      FlutwireBodyKind.form => _BodyMode.text,
      FlutwireBodyKind.multipart ||
      FlutwireBodyKind.image ||
      FlutwireBodyKind.binary => _BodyMode.recorded,
    };
  }

  _HeaderRow _row(String name, String value) => _HeaderRow(name, value)
    ..name.addListener(_changed)
    ..value.addListener(_changed);

  void _changed() {
    if (mounted) setState(() {});
  }

  void _addHeader() => setState(() => _headers.add(_row('', '')));

  void _removeHeader(_HeaderRow row) {
    setState(() => _headers.remove(row));
    row.dispose();
  }

  /// The address the editor holds, or null when it cannot be sent to.
  Uri? get _target {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  /// Whether [text] still holds what the redaction left in place of a secret,
  /// whether written out or percent-encoded in an address.
  static bool _holdsMask(String text, String mask) {
    if (mask.isEmpty) return false;
    if (text.contains(mask)) return true;
    try {
      return Uri.decodeFull(text).contains(mask);
    } on ArgumentError {
      return false;
    }
  }

  bool get _canSendRecordedBody =>
      _mode == _BodyMode.recorded && _recorded.loaded && !_recorded.truncated;

  Uint8List? get _bodyBytes {
    if (_mode == _BodyMode.text) {
      final text = _body.text;
      return text.isEmpty ? null : Uint8List.fromList(utf8.encode(text));
    }
    if (_canSendRecordedBody && _sendRecordedBody && !_recorded.isEmpty) {
      return _recorded.bytes;
    }
    return null;
  }

  FlutwireResend _request(Uri uri, {required bool withBody}) => FlutwireResend(
    from: widget.call.id,
    method: _method,
    uri: uri,
    headers: [
      for (final row in _headers) MapEntry(row.name.text, row.value.text),
    ],
    mask: context.session.config.redaction.mask,
    body: withBody ? _bodyBytes : null,
  );

  Future<void> _send() async {
    final target = _target;
    if (target == null) {
      setState(() => _triedToSend = true);
      return;
    }
    final s = context.strings;
    final session = context.session;
    final navigator = Navigator.of(context);
    final request = _request(target, withBody: true);
    setState(() => _sending = true);
    final int? id;
    try {
      id = await session.resend(request);
    } on Object {
      if (!mounted) return;
      setState(() => _sending = false);
      showToast(context, s.resendFailed);
      return;
    }
    if (!mounted) return;
    if (id == null) {
      showToast(context, s.resendNotRecorded);
      navigator.pop();
      return;
    }
    unawaited(
      navigator.pushReplacement(
        shellRoute(
          session,
          name: 'flutwire/call',
          child: CallDetailPage(callId: id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    final target = _target;
    final mask = context.session.config.redaction.mask;
    // Only the header fields decide what is hidden, so the body, which can be
    // large, is not read on every key.
    final hidden = _request(
      target ?? Uri.parse('https://invalid.invalid/'),
      withBody: false,
    ).hidden;
    return Scaffold(
      appBar: AppBar(title: Text(s.resend)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _RequestLine(
                method: _method,
                methods: {..._methods, widget.call.method}.toList(),
                onMethod: (method) => setState(() => _method = method),
                url: _url,
                showError: _triedToSend && target == null,
              ),
              if (_holdsMask(_url.text, mask)) ...[
                const SizedBox(height: 8),
                _Note(
                  icon: Icons.visibility_off_outlined,
                  text: s.resendUrlHidden(mask),
                ),
              ],
              if (target != null) ...[
                const SizedBox(height: 8),
                Text(
                  s.resendTarget(target.host),
                  style: t.body(size: 12, color: t.muted),
                ),
              ],
              const SizedBox(height: 20),
              _Heading(s.tabHeaders),
              const SizedBox(height: 8),
              for (final row in _headers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _HeaderField(
                    row: row,
                    hidden: isHiddenValue(
                      row.name.text.trim(),
                      row.value.text,
                      mask,
                    ),
                    onRemove: () => _removeHeader(row),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addHeader,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(s.addHeader),
                ),
              ),
              if (hidden.isNotEmpty) ...[
                const SizedBox(height: 8),
                _Note(
                  icon: Icons.visibility_off_outlined,
                  text: s.resendHiddenNote(hidden.join(', ')),
                ),
              ],
              const SizedBox(height: 20),
              _Heading(s.tabBody),
              const SizedBox(height: 8),
              ..._bodySection(context),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: t.ground,
          border: Border(top: BorderSide(color: t.line)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(_sending ? s.sending : s.send),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _bodySection(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    if (_mode == _BodyMode.text) {
      final mask = context.session.config.redaction.mask;
      return [
        // Typing over the mask takes the note away, so it follows the text.
        ListenableBuilder(
          listenable: _body,
          builder: (context, _) => _holdsMask(_body.text, mask)
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Note(
                    icon: Icons.visibility_off_outlined,
                    text: s.resendBodyHidden(mask),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (_recorded.truncated) ...[
          _Note(
            icon: Icons.content_cut_rounded,
            text: s.resendBodyCut(
              formatBytes(_recorded.bytes.length),
              formatBytes(_recorded.totalBytes),
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _body,
          minLines: 6,
          maxLines: 16,
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          enableSuggestions: false,
          style: t.mono(size: 12.5, color: t.ink),
        ),
      ];
    }
    final cut = !_canSendRecordedBody;
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
          border: Border.all(color: t.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cut
                  ? s.resendBinaryCut
                  : s.resendBinaryBody(formatBytes(_recorded.totalBytes)),
              style: t.body(size: 13.5, color: t.ink),
            ),
            if (!cut) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.resendSendBody,
                      style: t.body(size: 13.5, color: t.muted),
                    ),
                  ),
                  Switch(
                    value: _sendRecordedBody,
                    onChanged: (value) =>
                        setState(() => _sendRecordedBody = value),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: context.fw.label(color: context.fw.faint),
  );
}

class _RequestLine extends StatelessWidget {
  const _RequestLine({
    required this.method,
    required this.methods,
    required this.onMethod,
    required this.url,
    required this.showError,
  });

  final String method;
  final List<String> methods;
  final ValueChanged<String> onMethod;
  final TextEditingController url;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PopupMenuButton<String>(
          tooltip: s.method,
          initialValue: method,
          onSelected: onMethod,
          itemBuilder: (_) => [
            for (final m in methods)
              PopupMenuItem(value: m, child: MethodChip(m)),
          ],
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
              border: Border.all(color: t.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MethodChip(method),
                const SizedBox(width: 2),
                Icon(Icons.arrow_drop_down_rounded, color: t.muted),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: url,
            minLines: 1,
            maxLines: 4,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            style: t.mono(size: 12.5, color: t.ink),
            decoration: InputDecoration(
              hintText: s.url,
              errorText: showError ? s.resendBadUrl : null,
              errorMaxLines: 3,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderField extends StatelessWidget {
  const _HeaderField({
    required this.row,
    required this.hidden,
    required this.onRemove,
  });

  final _HeaderRow row;
  final bool hidden;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: TextField(
            controller: row.name,
            autocorrect: false,
            enableSuggestions: false,
            style: t.mono(size: 12.5, color: t.ink),
            decoration: InputDecoration(
              hintText: s.headerName,
              contentPadding: _fieldPadding,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: TextField(
            controller: row.value,
            minLines: 1,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            style: t.mono(size: 12.5, color: hidden ? t.warning : t.ink),
            decoration: InputDecoration(
              hintText: s.headerValue,
              contentPadding: _fieldPadding,
              fillColor: hidden ? t.tint(t.warning) : null,
              suffixIcon: hidden
                  ? Tooltip(
                      message: s.hiddenValue,
                      child: Icon(
                        Icons.visibility_off_outlined,
                        size: 18,
                        color: t.warning,
                        semanticLabel: s.hiddenValue,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        IconButton(
          tooltip: s.removeHeader,
          icon: const Icon(Icons.close_rounded),
          onPressed: onRemove,
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
        border: Border.all(color: t.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: t.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: t.body(size: 13, color: t.ink)),
          ),
        ],
      ),
    );
  }
}
