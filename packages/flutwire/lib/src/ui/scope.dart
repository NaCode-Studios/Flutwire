import 'package:flutter/widgets.dart';

import '../l10n/strings.dart';
import '../l10n/strings_en.dart';
import 'theme/tokens.dart';

/// Hands the strings of the inspector's language to everything below it.
class FlutwireScope extends InheritedWidget {
  /// Creates a scope that speaks [strings].
  const FlutwireScope({super.key, required this.strings, required super.child});

  /// The language of the inspector.
  final FlutwireStrings strings;

  /// The strings in force below [context], English when there is no scope.
  static FlutwireStrings stringsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FlutwireScope>()?.strings ??
      const FlutwireStringsEn();

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
}
