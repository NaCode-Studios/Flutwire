import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../intercept/rule.dart';
import '../../model/body.dart';
import '../../model/call.dart';
import '../../model/headers.dart';
import '../../session.dart';
import '../../util/format.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme/tokens.dart';
import '../widgets/method_chip.dart';
import '../widgets/request_fields.dart';

/// The longest a mock may wait before it answers.
const Duration _longestDelay = Duration(minutes: 10);

/// The route that opens the editor of [rule], or of a new rule of [kind] that
/// starts from [from].
Route<void> ruleEditorRoute(
  FlutwireSession session, {
  required FlutwireRuleKind kind,
  FlutwireRule? rule,
  FlutwireCall? from,
}) => shellRoute(
  session,
  name: 'flutwire/rule',
  child: RuleEditorPage(kind: kind, rule: rule, from: from),
);

/// The editor of a rule: which requests it is about, and for a mock, the
/// response it gives.
///
/// A new rule can start from a call: a breakpoint for requests like it, or a
/// mock that gives the response it got, which is then the stored response.
class RuleEditorPage extends StatefulWidget {
  /// Edits [rule], or makes a rule of [kind]. A new rule starts from [from],
  /// which must have its bodies loaded, when there is one.
  const RuleEditorPage({super.key, required this.kind, this.rule, this.from});

  /// What the rule does.
  final FlutwireRuleKind kind;

  /// The rule being edited, or null for a new one.
  final FlutwireRule? rule;

  /// The call a new rule is made from.
  final FlutwireCall? from;

  @override
  State<RuleEditorPage> createState() => _RuleEditorPageState();
}

class _RuleEditorPageState extends State<RuleEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _pattern;
  late final TextEditingController _status;
  late final TextEditingController _delay;
  late final TextEditingController _body;
  late final BodyEditMode _mode;
  final List<HeaderRowControllers> _headers = [];
  Uint8List _recordedBytes = Uint8List(0);
  FlutwireBody? _fromBody;
  String? _method;
  bool _triedToSave = false;

  bool get _isMock => widget.kind == FlutwireRuleKind.mock;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    final call = widget.from;
    final response = rule?.response ?? _responseOf(call);
    _name = TextEditingController(text: rule?.name ?? '')
      ..addListener(_changed);
    _pattern = TextEditingController(
      text: rule?.pattern ?? (call == null ? '' : _patternFor(call)),
    )..addListener(_changed);
    _method = rule == null ? call?.method : rule.method;
    _status = TextEditingController(text: '${response?.statusCode ?? 200}')
      ..addListener(_changed);
    _delay = TextEditingController(
      text: '${response?.delay.inMilliseconds ?? 0}',
    )..addListener(_changed);
    final body = rule == null
        ? call?.response?.body
        : FlutwireBody(bytes: response?.body ?? Uint8List(0));
    _fromBody = body;
    _mode = body == null ? BodyEditMode.text : BodyEditMode.of(body);
    _body = TextEditingController(
      text: _mode == BodyEditMode.text && body != null
          ? body.prettyText ?? body.text ?? ''
          : '',
    );
    _recordedBytes = body?.bytes ?? Uint8List(0);
    for (final field
        in response?.headers.entries ?? const <MapEntry<String, String>>[]) {
      if (servedHeadersLeftOut.contains(field.key.toLowerCase())) continue;
      _headers.add(_row(field.key, field.value));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    _status.dispose();
    _delay.dispose();
    _body.dispose();
    for (final row in _headers) {
      row.dispose();
    }
    super.dispose();
  }

  /// The response a mock made from [call] gives: the one the call got.
  static FlutwireMockResponse? _responseOf(FlutwireCall? call) {
    final response = call?.response;
    if (response == null) return null;
    return FlutwireMockResponse(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      headers: response.headers,
      body: response.body.bytes,
    );
  }

  /// A pattern for requests like [call]: its host and path, and any query.
  static String _patternFor(FlutwireCall call) {
    final port = call.uri.hasPort && call.uri.port != 0
        ? ':${call.uri.port}'
        : '';
    final path = call.uri.path.isEmpty ? '/' : call.uri.path;
    return '${call.uri.host}$port$path${call.uri.hasQuery ? '?*' : ''}';
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

  int? get _statusCode {
    final code = int.tryParse(_status.text.trim());
    return code != null && code >= 100 && code <= 599 ? code : null;
  }

  bool get _patternOk => _pattern.text.trim().isNotEmpty;

  Uint8List get _bodyBytes => _mode == BodyEditMode.text
      ? Uint8List.fromList(utf8.encode(_body.text))
      : _recordedBytes;

  void _save() {
    if (!_patternOk || (_isMock && _statusCode == null)) {
      setState(() => _triedToSave = true);
      return;
    }
    final rules = context.session.interception?.rules;
    if (rules == null) return;
    final existing = widget.rule;
    final response = _isMock
        ? FlutwireMockResponse(
            statusCode: _statusCode!,
            headers: FlutwireHeaders([
              for (final row in _headers)
                if (row.name.text.trim().isNotEmpty)
                  MapEntry(row.name.text.trim(), row.value.text),
            ]),
            body: _bodyBytes,
            delay: Duration(
              milliseconds: (int.tryParse(_delay.text.trim()) ?? 0).clamp(
                0,
                _longestDelay.inMilliseconds,
              ),
            ),
          )
        : null;
    final rule = FlutwireRule(
      id: existing?.id ?? rules.newId(),
      kind: widget.kind,
      pattern: _pattern.text.trim(),
      method: _method,
      name: _name.text.trim(),
      enabled: existing?.enabled ?? true,
      response: response,
    );
    if (existing == null) {
      rules.add(rule);
    } else {
      rules.update(rule);
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final rule = widget.rule;
    final rules = context.session.interception?.rules;
    if (rule == null || rules == null) return;
    final s = context.strings;
    final t = context.fw;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.ruleDeleteTitle),
        content: Text(rule.label),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete, style: TextStyle(color: t.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    rules.remove(rule.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isMock ? s.ruleEditMock : s.ruleEditBreakpoint),
        actions: [
          if (widget.rule != null)
            IconButton(
              tooltip: s.ruleDelete,
              icon: Icon(Icons.delete_outline_rounded, color: t.error),
              onPressed: () => unawaited(_delete()),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              FieldHeading(s.ruleName),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                style: t.mono(size: 12.5, color: t.ink),
              ),
              const SizedBox(height: 20),
              FieldHeading(s.rulePattern),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MethodPicker(
                    method: _method,
                    onChanged: (value) => setState(() => _method = value),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _pattern,
                      minLines: 1,
                      maxLines: 3,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: t.mono(size: 12.5, color: t.ink),
                      decoration: InputDecoration(
                        hintText: 'api.test/items/*',
                        errorText: _triedToSave && !_patternOk
                            ? s.rulePatternBad
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(s.rulePatternHelp, style: t.body(size: 12, color: t.muted)),
              if (_isMock) ..._mockFields(context),
            ],
          ),
        ),
      ),
      bottomNavigationBar: EditorBottomBar(
        child: FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(s.save),
        ),
      ),
    );
  }

  List<Widget> _mockFields(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    final body = _fromBody;
    return [
      const SizedBox(height: 20),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _status,
              keyboardType: TextInputType.number,
              style: t.mono(size: 12.5, color: t.ink),
              decoration: InputDecoration(
                labelText: s.ruleStatus,
                errorText: _triedToSave && _statusCode == null
                    ? s.ruleStatusBad
                    : null,
                errorMaxLines: 2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _delay,
              keyboardType: TextInputType.number,
              style: t.mono(size: 12.5, color: t.ink),
              decoration: InputDecoration(labelText: s.ruleDelay),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      FieldHeading(s.tabHeaders),
      const SizedBox(height: 8),
      for (final row in _headers)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: HeaderField(
            row: row,
            hidden: false,
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
      const SizedBox(height: 20),
      FieldHeading(s.tabBody),
      const SizedBox(height: 8),
      if (body != null && body.truncated) ...[
        FieldNote(
          icon: Icons.content_cut_rounded,
          text: s.resendBodyCut(
            formatBytes(body.bytes.length),
            formatBytes(body.totalBytes),
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (_mode == BodyEditMode.text)
        TextField(
          controller: _body,
          minLines: 6,
          maxLines: 16,
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          enableSuggestions: false,
          style: t.mono(size: 12.5, color: t.ink),
        )
      else
        FieldNote(
          icon: Icons.insert_drive_file_outlined,
          text: s.ruleBodyNotText,
        ),
    ];
  }
}

/// The choice of the method a rule is about, or of every method.
class _MethodPicker extends StatelessWidget {
  const _MethodPicker({required this.method, required this.onChanged});

  final String? method;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    return PopupMenuButton<String>(
      tooltip: s.method,
      initialValue: method ?? '',
      onSelected: (value) => onChanged(value.isEmpty ? null : value),
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text(s.ruleMethodAny)),
        for (final m in {...httpMethods, ?method})
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
            method == null
                ? Text(
                    'ANY',
                    style: t.mono(
                      size: 10.5,
                      weight: FontWeight.w600,
                      color: t.muted,
                      height: 1.2,
                    ),
                  )
                : MethodChip(method!),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, color: t.muted),
          ],
        ),
      ),
    );
  }
}
