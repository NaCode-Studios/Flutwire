import 'package:flutter/widgets.dart';

import '../l10n/lookup.dart';
import '../l10n/strings.dart';
import '../session.dart';
import 'theme/tokens.dart';

/// Hands the session and the strings of the inspector's language to everything
/// below it.
class FlutwireScope extends InheritedWidget {
  /// Creates a scope around [child] that speaks [strings] and works on
  /// [session].
  const FlutwireScope({
    super.key,
    required this.session,
    required this.strings,
    required super.child,
  });

  /// What the inspector works on.
  final FlutwireSession session;

  /// The language of the inspector.
  final FlutwireStrings strings;

  /// The session below [context]. It is an error to ask for it outside a scope:
  /// every screen of the inspector is built inside one.
  ///
  /// It does not subscribe [context] to the scope, because the session a scope
  /// holds does not change for as long as the scope lives. That also makes it
  /// safe to call from `initState`.
  static FlutwireSession sessionOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<FlutwireScope>();
    assert(scope != null, 'No FlutwireScope above this context.');
    return scope!.session;
  }

  /// The strings in force below [context], English when there is no scope.
  static FlutwireStrings stringsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FlutwireScope>()?.strings ??
      stringsFor(null);

  @override
  bool updateShouldNotify(FlutwireScope oldWidget) =>
      strings != oldWidget.strings;
}

/// Shorthands for what every inspector widget reads.
extension FlutwireContext on BuildContext {
  /// The tokens: colours, type and shapes.
  FlutwireTokens get fw => FlutwireTokens.of(this);

  /// The strings, in the inspector's language.
  FlutwireStrings get strings => FlutwireScope.stringsOf(this);

  /// What the inspector works on.
  FlutwireSession get session => FlutwireScope.sessionOf(this);
}
