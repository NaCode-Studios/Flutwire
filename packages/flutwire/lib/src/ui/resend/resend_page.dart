import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../intercept/breakpoints.dart';
import '../../model/body.dart';
import '../../model/call.dart';
import '../../resend.dart';
import '../../util/format.dart';
import '../actions.dart';
import '../detail/call_detail_page.dart';
import '../scope.dart';
import '../theme/tokens.dart';
import '../widgets/method_chip.dart';
import '../widgets/request_fields.dart';

/// A request opened for changes: a recorded call to be sent again, or a request
/// that a breakpoint holds before it leaves.
///
/// A call starts as it was: the same method, address, header fields and body.
/// A value the redaction hid is flagged and not sent, because Flutwire never
/// held it. What is sent is recorded as a new call that names this one.
///
/// A held request starts as the app made it, with the real values, because it
/// has not been recorded and nothing was hidden. Sending lets it go on as it is
/// now written, and stopping makes the app's call fail.
class ResendPage extends StatefulWidget {
  /// Opens [call], which must have its bodies loaded. With [held], the page is
  /// the editor of that held request and [call] describes it.
  const ResendPage({super.key, required this.call, this.held});

  /// The call to repeat.
  final FlutwireCall call;

  /// The request this page lets go, when it is one that a breakpoint holds.
  final FlutwireHeldRequest? held;

  @override
  State<ResendPage> createState() => _ResendPageState();
}

class _ResendPageState extends State<ResendPage> {
  late final TextEditingController _url;
  late final TextEditingController _body;
  late final BodyEditMode _mode;
  final List<HeaderRowControllers> _headers = [];
  late String _method;
  bool _sendRecordedBody = true;
  bool _sending = false;
  bool _triedToSend = false;

  FlutwireBody get _recorded => widget.call.request.body;

  /// What the redaction left in place of a secret. A held request has none.
  String get _mask =>
      widget.held == null ? context.session.config.redaction.mask : '';

  FlutwireBreakpoints? _breakpoints;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    final call = widget.call;
    if (widget.held != null) {
      _breakpoints = context.session.interception?.breakpoints
        ?..addListener(_heldChanged);
    }
    _method = call.method;
    _url = TextEditingController(text: call.uri.toString())
      ..addListener(_changed);
    _mode = BodyEditMode.of(_recorded);
    _body = TextEditingController(
      text: _mode == BodyEditMode.text ? _recorded.text ?? '' : '',
    );
    for (final field in call.request.headers.entries) {
      if (clientManagedHeaders.contains(field.key.toLowerCase())) continue;
      _headers.add(_row(field.key, field.value));
    }
  }

  @override
  void dispose() {
    _breakpoints?.removeListener(_heldChanged);
    _url.dispose();
    _body.dispose();
    for (final row in _headers) {
      row.dispose();
    }
    super.dispose();
  }

  HeaderRowControllers _row(String name, String value) =>
      HeaderRowControllers(name, value)
        ..name.addListener(_changed)
        ..value.addListener(_changed);

  void _changed() {
    if (mounted) setState(() {});
  }

  void _addHeader() => setState(() => _headers.add(_row('', '')));

  void _removeHeader(HeaderRowControllers row) {
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
      _mode == BodyEditMode.recorded &&
      _recorded.loaded &&
      !_recorded.truncated;

  Uint8List? get _bodyBytes {
    if (_mode == BodyEditMode.text) {
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
    mask: _mask,
    body: withBody ? _bodyBytes : null,
  );

  /// Closes the page when the request it edits was let go some other way: the
  /// app aborted it, or the client was shut down.
  void _heldChanged() {
    final held = widget.held;
    if (_leaving || held == null || _breakpoints?.find(held.id) != null) return;
    showToast(context, context.strings.heldGone);
    _leave();
  }

  /// Takes this page off the stack. The editor of the next held request can be
  /// pushed over it at the very moment this one is let go, and that one stays:
  /// this page is removed where it is.
  void _leave() {
    _leaving = true;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  /// Lets the held request go as it is written, and goes back.
  void _resume(FlutwireHeldRequest held, Uri target) {
    final request = _request(target, withBody: true);
    // The page goes first, because letting the request go can bring up the
    // editor of the next one.
    _leave();
    _breakpoints?.resume(
      held.id,
      held.copyWith(
        method: request.method,
        uri: request.uri,
        headers: request.headers,
        body: request.body ?? Uint8List(0),
      ),
    );
  }

  /// Stops the held request, so that the app's call fails, and goes back.
  void _stop(FlutwireHeldRequest held) {
    _leave();
    _breakpoints?.stop(held.id);
  }

  Future<void> _send() async {
    final target = _target;
    if (target == null) {
      setState(() => _triedToSend = true);
      return;
    }
    final held = widget.held;
    if (held != null) {
      _resume(held, target);
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
    unawaited(navigator.pushReplacement(callRoute(session, id)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    final target = _target;
    final mask = _mask;
    // Only the header fields decide what is hidden, so the body, which can be
    // large, is not read on every key.
    final hidden = _request(
      target ?? Uri.parse('https://invalid.invalid/'),
      withBody: false,
    ).hidden;
    return Scaffold(
      appBar: AppBar(title: Text(widget.held == null ? s.resend : s.heldTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (widget.held != null) ...[
                FieldNote(
                  icon: Icons.pause_circle_outline_rounded,
                  text: s.heldNote,
                ),
                const SizedBox(height: 16),
              ],
              _RequestLine(
                method: _method,
                methods: {...httpMethods, widget.call.method}.toList(),
                onMethod: (method) => setState(() => _method = method),
                url: _url,
                showError: _triedToSend && target == null,
              ),
              if (_holdsMask(_url.text, mask)) ...[
                const SizedBox(height: 8),
                FieldNote(
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
              FieldHeading(s.tabHeaders),
              const SizedBox(height: 8),
              for (final row in _headers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: HeaderField(
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
                FieldNote(
                  icon: Icons.visibility_off_outlined,
                  text: s.resendHiddenNote(hidden.join(', ')),
                ),
              ],
              const SizedBox(height: 20),
              FieldHeading(s.tabBody),
              const SizedBox(height: 8),
              ..._bodySection(context),
            ],
          ),
        ),
      ),
      // The stop button keeps its own width until it would crowd out the one
      // that sends, as it does in a long translation or with a large text size.
      bottomNavigationBar: EditorBottomBar(
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              if (widget.held case final held?) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
                  child: OutlinedButton.icon(
                    onPressed: () => _stop(held),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.error,
                      side: BorderSide(color: t.error.withValues(alpha: 0.5)),
                    ),
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: Text(s.heldStop),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
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
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _bodySection(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    if (_mode == BodyEditMode.text) {
      final mask = _mask;
      return [
        // Typing over the mask takes the note away, so it follows the text.
        ListenableBuilder(
          listenable: _body,
          builder: (context, _) => _holdsMask(_body.text, mask)
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FieldNote(
                    icon: Icons.visibility_off_outlined,
                    text: s.resendBodyHidden(mask),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (_recorded.truncated) ...[
          FieldNote(
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
