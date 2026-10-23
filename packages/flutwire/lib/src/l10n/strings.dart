import 'dart:ui' show Locale;

import 'strings_en.dart';
import 'strings_it.dart';

/// Every piece of text Flutwire shows, in one language.
///
/// To add a language, extend this class and pass an instance through
/// [FlutwireStrings.register]. English and Italian ship with the package.
abstract class FlutwireStrings {
  /// Creates a set of strings.
  const FlutwireStrings();

  static final Map<String, FlutwireStrings> _registered = {
    'en': const FlutwireStringsEn(),
    'it': const FlutwireStringsIt(),
  };

  /// Makes [strings] the text for [languageCode], replacing any earlier set.
  static void register(String languageCode, FlutwireStrings strings) =>
      _registered[languageCode] = strings;

  /// The strings for [locale], or English when the language is not known.
  static FlutwireStrings of(Locale? locale) =>
      _registered[locale?.languageCode] ?? const FlutwireStringsEn();

  /// The name of the notification channel on Android.
  String get channelName;

  /// What the notification channel is for, shown in the system settings.
  String get channelDescription;

  /// The title of the notification in the shade.
  String get notificationTitle;

  /// The label of the notification's clear button.
  String get clear;

  /// The label of the app icon shortcut.
  String get shortcutLabel;

  /// A line summarising the history: how many calls and how many went wrong.
  String summary({required int calls, required int failed});
}
