import 'package:flutter/material.dart';

import '../scope.dart';
import '../theme/tokens.dart';

/// The methods a picker offers, besides the one a call used.
const List<String> httpMethods = [
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
];

/// A header field is narrow, and its name is a long word in a monospaced face.
const EdgeInsets fieldPadding = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 12,
);

/// The two text fields of one header field being edited.
class HeaderRowControllers {
  /// Creates the fields, holding [name] and [value].
  HeaderRowControllers(String name, String value)
    : name = TextEditingController(text: name),
      value = TextEditingController(text: value);

  /// The name of the field.
  final TextEditingController name;

  /// The value of the field.
  final TextEditingController value;

  /// Releases both controllers.
  void dispose() {
    name.dispose();
    value.dispose();
  }
}

/// The small heading above a group of fields.
class FieldHeading extends StatelessWidget {
  /// Creates a heading that says [text].
  const FieldHeading(this.text, {super.key});

  /// What the heading says.
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: context.fw.label(color: context.fw.faint),
  );
}

/// One header field being edited: its name, its value and a way to remove it.
class HeaderField extends StatelessWidget {
  /// Creates the editor of [row]. A [hidden] value is marked as one the
  /// redaction took out, which cannot be sent.
  const HeaderField({
    super.key,
    required this.row,
    required this.hidden,
    required this.onRemove,
  });

  /// The fields being edited.
  final HeaderRowControllers row;

  /// Whether the value is what the redaction left in place of a secret.
  final bool hidden;

  /// Removes the header field.
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
              contentPadding: fieldPadding,
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
              contentPadding: fieldPadding,
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

/// A sentence that something needs a second look, with an icon.
class FieldNote extends StatelessWidget {
  /// Creates a note that says [text].
  const FieldNote({super.key, required this.icon, required this.text});

  /// The icon at the start.
  final IconData icon;

  /// What the note says.
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
