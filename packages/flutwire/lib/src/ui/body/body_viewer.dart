import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config.dart';
import '../../l10n/strings.dart';
import '../../model/body.dart';
import '../../model/call.dart';
import '../../util/format.dart';
import '../scope.dart';
import 'code_view.dart';
import 'copy.dart';
import 'fields_view.dart';
import 'hex_view.dart';
import 'highlight.dart';
import 'image_view.dart';
import 'json_model.dart';
import 'json_tree.dart';
import 'metrics.dart';
import 'parts_view.dart';
import 'quiet_note.dart';
import 'search.dart';

/// What the host app lets the viewer do with a body besides showing it.
///
/// Saving is the host's business, because how a file is written, shared or
/// handed to the system differs on every platform. A callback left null hides
/// its menu entry.
class FlutwireBodyActions {
  /// Creates the set of actions the host supports.
  const FlutwireBodyActions({this.onSaveBytes, this.onSaveText});

  /// Saves the bytes of the body as they were recorded, under [fileName], with
  /// the media type [mimeType].
  final Future<void> Function(
    Uint8List bytes,
    String fileName,
    String mimeType,
  )?
  onSaveBytes;

  /// Saves [text], which is the body indented, or as a decoder showed it,
  /// under [fileName].
  final Future<void> Function(String text, String fileName)? onSaveText;
}

enum _Mode { decoded, tree, pretty, raw, hex, fields, parts, preview }

enum _More { expandAll, collapseAll, lineNumbers }

/// One line of the copy or save menu: what it says and what it does.
class _Entry {
  const _Entry(this.label, this.run);

  final String label;
  final Future<void> Function() run;
}

/// A request or a response body, shown the way its content wants to be read.
///
/// JSON is a tree, indented text or the bytes as they came; XML and HTML are
/// colour-coded; a form is a list of fields; a multipart upload is a stack of
/// cards; an image is drawn; anything else is a hex dump. A decoder the app
/// registered can add a mode of its own for formats the inspector does not
/// know.
///
/// The viewer fills the height it is given and scrolls inside itself, so give
/// it a bounded one. It builds only the rows that are on screen, so a body of
/// any size opens at once.
class FlutwireBodyViewer extends StatefulWidget {
  /// Shows [body], which belongs to [call]. [isRequest] says which side of the
  /// call it is.
  const FlutwireBodyViewer({
    super.key,
    required this.call,
    required this.body,
    required this.isRequest,
    this.decoders = const [],
    this.actions = const FlutwireBodyActions(),
  });

  /// The call the body belongs to. Decoders receive it.
  final FlutwireCall call;

  /// The body, with its bytes loaded.
  final FlutwireBody body;

  /// Whether this is the request body, as opposed to the response body.
  final bool isRequest;

  /// The decoders to try, in order. The first that recognises the body wins.
  final List<FlutwireBodyDecoder> decoders;

  /// What the host can do with the body.
  final FlutwireBodyActions actions;

  @override
  State<FlutwireBodyViewer> createState() => _FlutwireBodyViewerState();
}

class _FlutwireBodyViewerState extends State<FlutwireBodyViewer> {
  final BodySearchController _search = BodySearchController();

  List<_Mode> _modes = const [];
  _Mode _mode = _Mode.raw;
  ({String name, String text})? _decoded;
  bool _searchOpen = false;
  bool _wrap = true;
  bool? _lineNumbers;

  JsonTreeController? _tree;
  FieldsModel? _fields;
  PartsModel? _parts;
  final Map<_Mode, TextSearchSource> _textSources = {};
  String? _prettyText;

  FlutwireBody get _body => widget.body;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(FlutwireBodyViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.body, widget.body) ||
        oldWidget.isRequest != widget.isRequest ||
        oldWidget.call.id != widget.call.id ||
        !listEquals(oldWidget.decoders, widget.decoders)) {
      // A call that is still running publishes a new body as it arrives.
      // Staying on the mode the user picked, with the search still open, is
      // what keeps the viewer usable while that happens.
      final sameSide =
          oldWidget.isRequest == widget.isRequest &&
          oldWidget.call.id == widget.call.id;
      _prepare(keepView: sameSide);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _tree?.dispose();
    super.dispose();
  }

  /// Works out what the body is and which modes it offers. Decoders are asked
  /// here, once per body, and never while building.
  void _prepare({bool keepView = false}) {
    final before = keepView ? _mode : null;
    _decoded = _decode();
    final base = _baseModes();
    _modes = [if (_decoded != null) _Mode.decoded, ...base];
    _tree = null;
    _fields = null;
    _parts = null;
    _prettyText = null;
    _textSources.clear();
    if (before != null && _modes.contains(before) && _isEnabled(before)) {
      _mode = before;
    } else {
      _mode = _decoded != null ? _Mode.decoded : _defaultMode(base);
      _searchOpen = false;
    }
    if (!_searchOpen) _search.clear();
    _search.attach(_sourceFor(_mode));
  }

  ({String name, String text})? _decode() {
    if (!_body.loaded || _body.isEmpty) return null;
    for (final decoder in widget.decoders) {
      try {
        final text = decoder.decode(
          widget.call,
          _body,
          isRequest: widget.isRequest,
        );
        if (text != null) return (name: decoder.name, text: text);
      } on Object {
        // A decoder is the app's code, and it may fail on a body it half
        // recognises. The inspector shows the body undecoded instead.
      }
    }
    return null;
  }

  List<_Mode> _baseModes() => switch (_body.kind) {
    FlutwireBodyKind.json => const [_Mode.tree, _Mode.pretty, _Mode.raw],
    FlutwireBodyKind.xml => const [_Mode.pretty, _Mode.raw],
    FlutwireBodyKind.html || FlutwireBodyKind.text => const [_Mode.raw],
    FlutwireBodyKind.form => const [_Mode.fields, _Mode.raw],
    FlutwireBodyKind.multipart => const [_Mode.parts, _Mode.hex],
    FlutwireBodyKind.image => const [_Mode.preview, _Mode.hex],
    FlutwireBodyKind.binary => const [_Mode.hex],
    FlutwireBodyKind.empty => const [],
  };

  _Mode _defaultMode(List<_Mode> base) {
    if (base.isEmpty) return _Mode.raw;
    if (_body.kind == FlutwireBodyKind.json) {
      return _body.isValidJson ? _Mode.tree : _Mode.raw;
    }
    return base.first;
  }

  /// A cut or malformed JSON body has no tree and no indented form.
  bool _isEnabled(_Mode mode) =>
      _body.kind != FlutwireBodyKind.json ||
      (mode != _Mode.tree && mode != _Mode.pretty) ||
      _body.isValidJson;

  bool _isSearchable(_Mode mode) => mode != _Mode.hex && mode != _Mode.preview;

  bool _isCode(_Mode mode) =>
      mode == _Mode.decoded || mode == _Mode.pretty || mode == _Mode.raw;

  String get _pretty {
    return _prettyText ??= () {
      try {
        return _body.prettyText ?? _body.text ?? '';
      } on Object {
        // JSON nested deeper than the encoder can follow. The text as it came
        // is still worth showing.
        return _body.text ?? '';
      }
    }();
  }

  JsonTreeController get _treeController =>
      _tree ??= JsonTreeController(_body.jsonValue);

  FieldsModel get _fieldsModel => _fields ??= FieldsModel(_body.formFields);

  PartsModel get _partsModel => _parts ??= PartsModel(_body);

  TextSearchSource _textSource(_Mode mode, String text) =>
      _textSources.putIfAbsent(mode, () => TextSearchSource(text));

  String _textOf(_Mode mode) => switch (mode) {
    _Mode.decoded => _decoded?.text ?? '',
    _Mode.pretty => _pretty,
    _ => _body.text ?? '',
  };

  BodySearchSource? _sourceFor(_Mode mode) => switch (mode) {
    _Mode.decoded ||
    _Mode.pretty ||
    _Mode.raw => _textSource(mode, _textOf(mode)),
    _Mode.tree => _treeController,
    _Mode.fields => _fieldsModel,
    _Mode.parts => _partsModel,
    _Mode.hex || _Mode.preview => null,
  };

  void _setMode(_Mode mode) {
    if (mode == _mode || !_isEnabled(mode)) return;
    setState(() {
      _mode = mode;
      final source = _sourceFor(mode);
      if (source == null) {
        _searchOpen = false;
        _search.clear();
      }
      _search.attach(source);
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) _search.clear();
    });
  }

  CodeLanguage get _language => switch (_body.kind) {
    FlutwireBodyKind.json => CodeLanguage.json,
    FlutwireBodyKind.xml || FlutwireBodyKind.html => CodeLanguage.xml,
    _ => CodeLanguage.plain,
  };

  String _fileName({String? extension}) {
    final side = widget.isRequest ? 'request' : 'response';
    return 'flutwire-${widget.call.id}-$side.${extension ?? _extension()}';
  }

  String _extension() {
    switch (_body.kind) {
      case FlutwireBodyKind.json:
        return 'json';
      case FlutwireBodyKind.xml:
        return _body.mimeType == 'image/svg+xml' ? 'svg' : 'xml';
      case FlutwireBodyKind.html:
        return 'html';
      case FlutwireBodyKind.text:
      case FlutwireBodyKind.form:
        return 'txt';
      case FlutwireBodyKind.image:
        return switch (_body.mimeType) {
          'image/png' => 'png',
          'image/jpeg' => 'jpg',
          'image/gif' => 'gif',
          'image/webp' => 'webp',
          'image/bmp' => 'bmp',
          _ => 'img',
        };
      case FlutwireBodyKind.multipart:
      case FlutwireBodyKind.binary:
      case FlutwireBodyKind.empty:
        return 'bin';
    }
  }

  List<_Entry> _copyEntries(BuildContext context) {
    final strings = context.strings;
    final raw = _body.text;
    _Entry entry(String label, String Function() text) =>
        _Entry(label, () => copyToClipboard(context, text()));
    switch (_mode) {
      case _Mode.hex:
        return [entry(strings.copyBody, () => hexDump(_body.bytes))];
      case _Mode.preview:
      case _Mode.parts:
        return const [];
      case _Mode.decoded:
        return [
          entry(strings.copyBody, () => _decoded?.text ?? ''),
          if (raw != null) entry(strings.copyRaw, () => raw),
        ];
      case _Mode.tree:
      case _Mode.pretty:
      case _Mode.raw:
      case _Mode.fields:
        if (raw == null) return const [];
        // Offer the indented form only when it differs from what was sent.
        final pretty = _pretty;
        if (pretty != raw) {
          return [
            entry(strings.copyFormatted, () => pretty),
            entry(strings.copyRaw, () => raw),
          ];
        }
        return [entry(strings.copyBody, () => raw)];
    }
  }

  bool get _canCopy => switch (_mode) {
    _Mode.hex || _Mode.decoded => true,
    _Mode.preview || _Mode.parts => false,
    _ => _body.text != null,
  };

  List<_Entry> _saveEntries(BuildContext context) {
    final strings = context.strings;
    final actions = widget.actions;
    final onBytes = actions.onSaveBytes;
    final onText = actions.onSaveText;
    final entries = <_Entry>[];
    if (onBytes != null && _body.bytes.isNotEmpty) {
      entries.add(
        _Entry(
          strings.saveBody,
          () => onBytes(
            _body.bytes,
            _fileName(),
            _body.mimeType ?? 'application/octet-stream',
          ),
        ),
      );
    }
    final decoded = _mode == _Mode.decoded;
    final text = decoded
        ? _decoded?.text
        : (_body.text == null ? null : _pretty);
    if (onText != null &&
        text != null &&
        (onBytes == null || text != _body.text)) {
      entries.add(
        _Entry(
          onBytes == null ? strings.saveBody : strings.saveFormatted,
          () => onText(text, _fileName(extension: decoded ? 'txt' : null)),
        ),
      );
    }
    return entries;
  }

  /// Whether the save menu has something to offer. It is cheap on purpose: it
  /// runs on every build, and the indented text it would otherwise compare
  /// is worked out only when the menu opens.
  bool get _canSave {
    final actions = widget.actions;
    if (actions.onSaveBytes != null && _body.bytes.isNotEmpty) return true;
    return actions.onSaveText != null &&
        (_mode == _Mode.decoded || _body.text != null);
  }

  /// Runs a menu entry, and says so when the host's save fails.
  Future<void> _run(_Entry entry) async {
    try {
      await entry.run();
    } on Object {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(content: Text(context.strings.failed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final Widget child;
    if (_body.isEmpty) {
      child = QuietNote(strings.bodyEmpty);
    } else if (!_body.loaded) {
      child = QuietNote(strings.bodyNotLoaded);
    } else {
      child = LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < bodyNarrowWidth;
          return Column(
            children: [
              _buildToolbar(context, narrow),
              ..._buildBanners(context),
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey<String>('flutwire.body.content.${_mode.name}'),
                  child: _buildContent(context, narrow),
                ),
              ),
              if (_searchOpen)
                BodySearchBar(controller: _search, onClose: _toggleSearch),
            ],
          );
        },
      );
    }
    return Material(color: context.fw.surface, child: child);
  }

  Widget _buildContent(BuildContext context, bool narrow) {
    switch (_mode) {
      case _Mode.decoded:
      case _Mode.pretty:
      case _Mode.raw:
        return CodeView(
          text: _textOf(_mode),
          language: _mode == _Mode.decoded ? CodeLanguage.plain : _language,
          wrap: _wrap,
          lineNumbers: _lineNumbers ?? !narrow,
          search: _search,
        );
      case _Mode.tree:
        return JsonTree(controller: _treeController, search: _search);
      case _Mode.hex:
        return HexView(bytes: _body.bytes);
      case _Mode.fields:
        return FieldsView(model: _fieldsModel, search: _search);
      case _Mode.parts:
        return PartsView(model: _partsModel, search: _search);
      case _Mode.preview:
        return ImageView(
          bytes: _body.bytes,
          onShowHex: () => _setMode(_Mode.hex),
        );
    }
  }

  List<Widget> _buildBanners(BuildContext context) {
    final strings = context.strings;
    final tokens = context.fw;
    final decoded = _decoded;
    return [
      if (_body.truncated)
        _Banner(
          icon: Icons.content_cut_rounded,
          color: tokens.warning,
          text: strings.bodyTruncated(
            formatBytes(_body.keptBytes),
            formatBytes(_body.totalBytes),
          ),
        ),
      if (decoded != null)
        _Banner(
          icon: Icons.auto_awesome_rounded,
          color: tokens.copperTone,
          text: strings.bodyDecodedBy(decoded.name),
          actionLabel: _mode == _Mode.decoded
              ? strings.showRaw
              : strings.showDecoded,
          onAction: () => _setMode(
            _mode == _Mode.decoded
                ? _defaultMode(_modes.skip(1).toList())
                : _Mode.decoded,
          ),
        ),
      // The decoded text of a body that is not text deserves a word about what
      // is underneath it. The modes that draw the bytes say so themselves.
      if (_mode == _Mode.decoded && _body.text == null)
        _Banner(
          icon: Icons.data_object_rounded,
          color: tokens.info,
          text: strings.bodyBinary(
            formatBytes(_body.totalBytes),
            _body.mimeType ?? '',
          ),
        ),
    ];
  }

  String _label(_Mode mode, FlutwireStrings strings) => switch (mode) {
    _Mode.decoded => strings.viewDecoded,
    _Mode.tree => strings.viewTree,
    _Mode.pretty => strings.viewPretty,
    _Mode.raw => strings.viewRaw,
    _Mode.hex => strings.viewHex,
    _Mode.fields => strings.viewFields,
    _Mode.parts => strings.viewParts,
    _Mode.preview => strings.viewPreview,
  };

  Widget _buildToolbar(BuildContext context, bool narrow) {
    final tokens = context.fw;
    final strings = context.strings;
    final copy = _canCopy;
    final save = _canSave;
    final more = _mode == _Mode.tree || _isCode(_mode);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The chips wrap onto a second line on a narrow screen rather than
          // scrolling: a mode that is out of sight is a mode nobody finds.
          Expanded(
            child: Wrap(
              spacing: 4,
              children: [
                for (final mode in _modes)
                  _ModeChip(
                    key: ValueKey<String>('flutwire.body.mode.${mode.name}'),
                    label: _label(mode, strings),
                    selected: mode == _mode,
                    enabled: _isEnabled(mode),
                    onTap: () => _setMode(mode),
                  ),
              ],
            ),
          ),
          if (_isSearchable(_mode))
            _ToolButton(
              icon: Icons.search_rounded,
              tooltip: strings.search,
              selected: _searchOpen,
              onPressed: _toggleSearch,
            ),
          if (_isCode(_mode))
            _ToolButton(
              icon: Icons.wrap_text_rounded,
              tooltip: strings.wrapLines,
              selected: _wrap,
              onPressed: () => setState(() => _wrap = !_wrap),
            ),
          if (copy)
            _MenuButton(
              icon: Icons.copy_rounded,
              tooltip: strings.copy,
              entries: () => _copyEntries(context),
              onSelected: _run,
            ),
          if (save)
            _MenuButton(
              icon: Icons.save_alt_rounded,
              tooltip: strings.save,
              entries: () => _saveEntries(context),
              onSelected: _run,
            ),
          if (more) _buildMore(context, narrow),
        ],
      ),
    );
  }

  Widget _buildMore(BuildContext context, bool narrow) {
    final strings = context.strings;
    final tokens = context.fw;
    final lineNumbers = _lineNumbers ?? !narrow;
    return PopupMenuButton<_More>(
      tooltip: strings.moreActions,
      padding: EdgeInsets.zero,
      onSelected: (action) {
        switch (action) {
          case _More.expandAll:
            _treeController.expandAll();
          case _More.collapseAll:
            _treeController.collapseAll();
          case _More.lineNumbers:
            setState(() => _lineNumbers = !lineNumbers);
        }
      },
      itemBuilder: (context) => [
        if (_mode == _Mode.tree) ...[
          PopupMenuItem(value: _More.expandAll, child: Text(strings.expandAll)),
          PopupMenuItem(
            value: _More.collapseAll,
            child: Text(strings.collapseAll),
          ),
        ] else
          CheckedPopupMenuItem(
            value: _More.lineNumbers,
            checked: lineNumbers,
            child: Text(strings.lineNumbers),
          ),
      ],
      child: _ToolIcon(icon: Icons.more_vert_rounded, color: tokens.muted),
    );
  }
}

/// One mode of the viewer, as a pill the user can pick.
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    final color = !enabled
        ? tokens.faint.withValues(alpha: 0.6)
        : selected
        ? tokens.ink
        : tokens.muted;
    // The pill is the touch target: 40 logical pixels tall, like the icon
    // buttons beside it, so the ink of a press fills it exactly.
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? tokens.lineStrong : Colors.transparent,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected ? tokens.raised : Colors.transparent,
        shape: shape,
        animationDuration: Duration.zero,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: shape,
          child: SizedBox(
            height: 40,
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  label,
                  style: tokens.mono(
                    size: 12.5,
                    weight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon button of the toolbar: 40 logical pixels square, quiet until it is
/// switched on.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: selected ? tokens.ink : tokens.muted,
        backgroundColor: selected ? tokens.raised : Colors.transparent,
        fixedSize: const Size.square(40),
        minimumSize: const Size.square(40),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: 40, child: Icon(icon, size: 20, color: color));
}

/// A toolbar button that opens a menu of [_Entry]s, built when it opens.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.tooltip,
    required this.entries,
    required this.onSelected,
  });

  final IconData icon;
  final String tooltip;
  final List<_Entry> Function() entries;
  final Future<void> Function(_Entry entry) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Entry>(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final entry in entries())
          PopupMenuItem(value: entry, child: Text(entry.label)),
      ],
      child: _ToolIcon(icon: icon, color: context.fw.muted),
    );
  }
}

/// A note above the content: the body was cut, or it was decoded.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.only(left: 12),
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        color: tokens.tint(color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                text,
                style: tokens.body(size: 12.5, color: tokens.text),
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: tokens.syntaxKey,
                minimumSize: const Size(40, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: tokens.body(size: 12.5, weight: FontWeight.w600),
              ),
              child: Text(actionLabel!),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}
