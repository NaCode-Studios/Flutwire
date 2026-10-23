import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config.dart';
import '../../l10n/strings.dart';
import '../../model/body.dart';
import '../../model/call.dart';
import '../../util/format.dart';
import '../scope.dart';
import 'body_files.dart';
import 'body_modes.dart';
import 'body_toolbar.dart';
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

enum _More { expandAll, collapseAll, lineNumbers }

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

  late BodyModes _modes;
  BodyMode _mode = BodyMode.raw;
  ({String name, String text})? _decoded;
  bool _searchOpen = false;
  bool _wrap = true;
  bool? _lineNumbers;

  JsonTreeController? _tree;
  FieldsModel? _fields;
  PartsModel? _parts;
  final Map<BodyMode, TextSearchSource> _textSources = {};
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
    _modes = BodyModes(_body, hasDecoded: _decoded != null);
    _tree = null;
    _fields = null;
    _parts = null;
    _prettyText = null;
    _textSources.clear();
    if (before != null &&
        _modes.all.contains(before) &&
        _modes.isEnabled(before)) {
      _mode = before;
    } else {
      _mode = _modes.initial;
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

  TextSearchSource _textSource(BodyMode mode, String text) =>
      _textSources.putIfAbsent(mode, () => TextSearchSource(text));

  String _textOf(BodyMode mode) => switch (mode) {
    BodyMode.decoded => _decoded?.text ?? '',
    BodyMode.pretty => _pretty,
    _ => _body.text ?? '',
  };

  BodySearchSource? _sourceFor(BodyMode mode) => switch (mode) {
    BodyMode.decoded ||
    BodyMode.pretty ||
    BodyMode.raw => _textSource(mode, _textOf(mode)),
    BodyMode.tree => _treeController,
    BodyMode.fields => _fieldsModel,
    BodyMode.parts => _partsModel,
    BodyMode.hex || BodyMode.preview => null,
  };

  void _setMode(BodyMode mode) {
    if (mode == _mode || !_modes.isEnabled(mode)) return;
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

  String _fileName({String? extension}) => bodyFileName(
    widget.call,
    _body,
    isRequest: widget.isRequest,
    extension: extension,
  );

  List<MenuEntry> _copyEntries(BuildContext context) {
    final strings = context.strings;
    final raw = _body.text;
    MenuEntry entry(String label, String Function() text) =>
        MenuEntry(label, () => copyToClipboard(context, text()));
    switch (_mode) {
      case BodyMode.hex:
        return [entry(strings.copyBody, () => hexDump(_body.bytes))];
      case BodyMode.preview:
      case BodyMode.parts:
        return const [];
      case BodyMode.decoded:
        return [
          entry(strings.copyBody, () => _decoded?.text ?? ''),
          if (raw != null) entry(strings.copyRaw, () => raw),
        ];
      case BodyMode.tree:
      case BodyMode.pretty:
      case BodyMode.raw:
      case BodyMode.fields:
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
    BodyMode.hex || BodyMode.decoded => true,
    BodyMode.preview || BodyMode.parts => false,
    _ => _body.text != null,
  };

  List<MenuEntry> _saveEntries(BuildContext context) {
    final strings = context.strings;
    final actions = widget.actions;
    final onBytes = actions.onSaveBytes;
    final onText = actions.onSaveText;
    final entries = <MenuEntry>[];
    if (onBytes != null && _body.bytes.isNotEmpty) {
      entries.add(
        MenuEntry(
          strings.saveBody,
          () => onBytes(
            _body.bytes,
            _fileName(),
            _body.mimeType ?? 'application/octet-stream',
          ),
        ),
      );
    }
    final decoded = _mode == BodyMode.decoded;
    final text = decoded
        ? _decoded?.text
        : (_body.text == null ? null : _pretty);
    if (onText != null &&
        text != null &&
        (onBytes == null || text != _body.text)) {
      entries.add(
        MenuEntry(
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
        (_mode == BodyMode.decoded || _body.text != null);
  }

  /// Runs a menu entry, and says so when the host's save fails.
  Future<void> _run(MenuEntry entry) async {
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
      case BodyMode.decoded:
      case BodyMode.pretty:
      case BodyMode.raw:
        return CodeView(
          text: _textOf(_mode),
          language: _mode == BodyMode.decoded ? CodeLanguage.plain : _language,
          wrap: _wrap,
          lineNumbers: _lineNumbers ?? !narrow,
          search: _search,
        );
      case BodyMode.tree:
        return JsonTree(controller: _treeController, search: _search);
      case BodyMode.hex:
        return HexView(bytes: _body.bytes);
      case BodyMode.fields:
        return FieldsView(model: _fieldsModel, search: _search);
      case BodyMode.parts:
        return PartsView(model: _partsModel, search: _search);
      case BodyMode.preview:
        return ImageView(
          bytes: _body.bytes,
          onShowHex: () => _setMode(BodyMode.hex),
        );
    }
  }

  List<Widget> _buildBanners(BuildContext context) {
    final strings = context.strings;
    final tokens = context.fw;
    final decoded = _decoded;
    return [
      if (_body.truncated)
        NoteBanner(
          icon: Icons.content_cut_rounded,
          color: tokens.warning,
          text: strings.bodyTruncated(
            formatBytes(_body.keptBytes),
            formatBytes(_body.totalBytes),
          ),
        ),
      if (decoded != null)
        NoteBanner(
          icon: Icons.auto_awesome_rounded,
          color: tokens.copperTone,
          text: strings.bodyDecodedBy(decoded.name),
          actionLabel: _mode == BodyMode.decoded
              ? strings.showRaw
              : strings.showDecoded,
          onAction: () => _setMode(
            _mode == BodyMode.decoded ? _modes.undecoded : BodyMode.decoded,
          ),
        ),
      // The decoded text of a body that is not text deserves a word about what
      // is underneath it. The modes that draw the bytes say so themselves.
      if (_mode == BodyMode.decoded && _body.text == null)
        NoteBanner(
          icon: Icons.data_object_rounded,
          color: tokens.info,
          text: strings.bodyBinary(
            formatBytes(_body.totalBytes),
            _body.mimeType ?? '',
          ),
        ),
    ];
  }

  String _label(BodyMode mode, FlutwireStrings strings) => switch (mode) {
    BodyMode.decoded => strings.viewDecoded,
    BodyMode.tree => strings.viewTree,
    BodyMode.pretty => strings.viewPretty,
    BodyMode.raw => strings.viewRaw,
    BodyMode.hex => strings.viewHex,
    BodyMode.fields => strings.viewFields,
    BodyMode.parts => strings.viewParts,
    BodyMode.preview => strings.viewPreview,
  };

  Widget _buildToolbar(BuildContext context, bool narrow) {
    final tokens = context.fw;
    final strings = context.strings;
    final copy = _canCopy;
    final save = _canSave;
    final more = _mode == BodyMode.tree || _mode.isCode;
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
                for (final mode in _modes.all)
                  ModeChip(
                    key: ValueKey<String>('flutwire.body.mode.${mode.name}'),
                    label: _label(mode, strings),
                    selected: mode == _mode,
                    enabled: _modes.isEnabled(mode),
                    onTap: () => _setMode(mode),
                  ),
              ],
            ),
          ),
          if (_mode.isSearchable)
            ToolButton(
              icon: Icons.search_rounded,
              tooltip: strings.search,
              selected: _searchOpen,
              onPressed: _toggleSearch,
            ),
          if (_mode.isCode)
            ToolButton(
              icon: Icons.wrap_text_rounded,
              tooltip: strings.wrapLines,
              selected: _wrap,
              onPressed: () => setState(() => _wrap = !_wrap),
            ),
          if (copy)
            MenuButton(
              icon: Icons.copy_rounded,
              tooltip: strings.copy,
              entries: () => _copyEntries(context),
              onSelected: _run,
            ),
          if (save)
            MenuButton(
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
        if (_mode == BodyMode.tree) ...[
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
      child: ToolIcon(icon: Icons.more_vert_rounded, color: tokens.muted),
    );
  }
}
