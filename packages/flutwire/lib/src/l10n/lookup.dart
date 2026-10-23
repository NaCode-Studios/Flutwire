import 'dart:ui' show Locale;

import 'strings.dart';
import 'strings_en.dart';
import 'strings_it.dart';

/// The strings for [locale], or English when the language is not one Flutwire
/// ships.
FlutwireStrings stringsFor(Locale? locale) => switch (locale?.languageCode) {
  'it' => const FlutwireStringsIt(),
  _ => const FlutwireStringsEn(),
};
