import 'package:flutter/material.dart';

import '../../flutwire.dart';
import '../../model/headers.dart';
import '../actions.dart';
import '../scope.dart';

/// The header fields of a request or a response, one per row. Tapping a row
/// copies it. A value the redaction policy hid is marked as hidden.
class HeadersView extends StatelessWidget {
  /// Creates the view for [headers].
  const HeadersView({super.key, required this.headers});

  /// The fields to show.
  final FlutwireHeaders headers;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    if (headers.isEmpty) {
      return Center(
        child: Text(s.noHeaders, style: t.body(color: t.faint)),
      );
    }
    final mask = Flutwire.config.redaction.mask;
    final fields = headers.entries.toList();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: fields.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: [
                Text('${fields.length}', style: t.label(color: t.faint)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => copyText(
                    context,
                    fields.map((e) => '${e.key}: ${e.value}').join('\n'),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text(s.copy),
                ),
              ],
            ),
          );
        }
        final field = fields[index - 1];
        final hidden = field.value == mask;
        return InkWell(
          onTap: () => copyText(context, '${field.key}: ${field.value}'),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.key,
                  style: t.mono(
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: t.syntaxKey,
                  ),
                ),
                const SizedBox(height: 3),
                hidden
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: t.raised,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: t.lineStrong),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 13,
                              color: t.faint,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              s.redacted,
                              style: t.mono(size: 11.5, color: t.muted),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        field.value,
                        style: t.mono(size: 12.5, color: t.ink),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }
}
