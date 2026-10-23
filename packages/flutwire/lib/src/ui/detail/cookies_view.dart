import 'package:flutter/material.dart';

import '../../model/cookies.dart';
import '../actions.dart';
import '../scope.dart';

/// The cookies a call sent or set, with their attributes.
class CookiesView extends StatelessWidget {
  /// Creates the view for [cookies].
  const CookiesView({super.key, required this.cookies});

  /// The cookies to show.
  final List<FlutwireCookie> cookies;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    if (cookies.isEmpty) {
      return Center(
        child: Text(s.noCookies, style: t.body(color: t.faint)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: cookies.length,
      itemBuilder: (context, index) {
        final cookie = cookies[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => copyText(context, '${cookie.name}=${cookie.value}'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cookie.name,
                    style: t.mono(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: t.syntaxKey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(cookie.value, style: t.mono(size: 12.5, color: t.ink)),
                  if (cookie.attributes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final attribute in cookie.attributes)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: t.raised,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              attribute,
                              style: t.mono(size: 11, color: t.muted),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
