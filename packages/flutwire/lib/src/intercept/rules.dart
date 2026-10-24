import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../store/preferences.dart';
import 'rule.dart';

/// The rules the user made to answer requests or to hold them, kept next to the
/// history so that they are there the next time the app runs.
///
/// The newest rule comes first, and the first rule in force that matches a
/// request is the one that acts, so a rule made for one address wins over an
/// older one made for all of them.
final class FlutwireRules extends ChangeNotifier {
  /// Creates the list of rules, with what [preferences] kept from before.
  FlutwireRules([this._preferences]) {
    _rules.addAll(_read(_preferences));
  }

  static const String _key = 'rules';

  final FlutwirePreferences? _preferences;
  final List<FlutwireRule> _rules = [];
  int _issued = 0;

  /// Every rule, the newest first.
  List<FlutwireRule> get all => List.unmodifiable(_rules);

  /// How many rules are in force.
  int get activeCount => _rules.where((rule) => rule.enabled).length;

  /// The rule with [id], or null.
  FlutwireRule? find(String id) {
    for (final rule in _rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }

  /// The mock in force that answers a request with [method] to [uri], or null.
  FlutwireRule? mockFor(String method, Uri uri) =>
      _firstMatch(FlutwireRuleKind.mock, method, uri);

  /// The breakpoint in force that holds a request with [method] to [uri], or
  /// null.
  FlutwireRule? breakpointFor(String method, Uri uri) =>
      _firstMatch(FlutwireRuleKind.breakpoint, method, uri);

  /// An id no other rule has.
  String newId() =>
      'r${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${(_issued++).toRadixString(36)}';

  /// Adds [rule] in front of the others.
  void add(FlutwireRule rule) {
    _rules.insert(0, rule);
    _changed();
  }

  /// Replaces the rule that has the id of [rule].
  void update(FlutwireRule rule) {
    final index = _rules.indexWhere((other) => other.id == rule.id);
    if (index < 0) return;
    _rules[index] = rule;
    _changed();
  }

  /// Turns the rule with [id] on or off.
  void setEnabled(String id, {required bool enabled}) {
    final rule = find(id);
    if (rule == null || rule.enabled == enabled) return;
    update(rule.copyWith(enabled: enabled));
  }

  /// Removes the rule with [id].
  void remove(String id) {
    final before = _rules.length;
    _rules.removeWhere((rule) => rule.id == id);
    if (_rules.length != before) _changed();
  }

  FlutwireRule? _firstMatch(FlutwireRuleKind kind, String method, Uri uri) {
    for (final rule in _rules) {
      if (rule.enabled && rule.kind == kind && rule.matches(method, uri)) {
        return rule;
      }
    }
    return null;
  }

  void _changed() {
    unawaited(
      _preferences?.write(
        _key,
        _rules.isEmpty
            ? null
            : jsonEncode([for (final rule in _rules) rule.toJson()]),
      ),
    );
    notifyListeners();
  }

  /// What was kept, leaving out whatever cannot be read.
  static List<FlutwireRule> _read(FlutwirePreferences? preferences) {
    final raw = preferences?.read(_key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return const [];
      return [for (final entry in decoded) ?FlutwireRule.fromJson(entry)];
    } on FormatException {
      return const [];
    }
  }
}
