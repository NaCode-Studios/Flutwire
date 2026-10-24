import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;

import 'store/preferences.dart';

/// Where the docked inspector sits, in relation to the app.
enum FlutwireDockSide {
  /// To the right of the app, full height.
  right,

  /// Under the app, full width.
  bottom,
}

/// The panel the inspector can sit in beside the app, so that the app and its
/// traffic are in view together.
///
/// The dock only holds the choices: whether the panel is open, which side it is
/// on, how much of the screen it takes, and whether the inspector opens in it
/// the next time. The widget that lays the panel out beside the app is the one
/// `Flutwire.builder` gives the app, and the dock can be used only while one is
/// there. What the user chose is kept next to the history, so it holds from one
/// run of the app to the next.
final class FlutwireDock extends ChangeNotifier {
  /// Creates a dock that keeps its choices in [preferences], if it has any.
  FlutwireDock([this._preferences])
    : _side = _readSide(_preferences),
      _extent = _readExtent(_preferences),
      _prefersDock = _preferences?.read(_modeKey) == _dockedValue;

  static const String _sideKey = 'dockSide';
  static const String _extentKey = 'dockExtent';
  static const String _modeKey = 'dockMode';
  static const String _dockedValue = 'docked';

  /// The share of the screen the panel takes until the user resizes it.
  static const double defaultExtent = 0.42;

  /// The least share of the screen the panel can take.
  static const double minExtent = 0.2;

  /// The most share of the screen the panel can take.
  static const double maxExtent = 0.8;

  /// From this width on, a screen puts the panel on the right, unless the user
  /// chose a side. A narrower one puts it at the bottom, where a phone has the
  /// room.
  static const double wideFrom = 900;

  /// The narrowest screen with room for the panel and the app side by side.
  /// Narrower than this the panel goes at the bottom whatever side was chosen,
  /// because beside the app it would leave neither of them a usable width.
  static const double besideFrom = 600;

  final FlutwirePreferences? _preferences;
  FlutwireDockSide? _side;
  FlutwireDockSide _resolved = FlutwireDockSide.bottom;
  double _extent;
  bool _prefersDock;
  bool _isOpen = false;
  int _hosts = 0;
  double _screenWidth = double.infinity;

  /// Whether the panel is on screen.
  bool get isOpen => _isOpen;

  /// Whether there is something to dock into: an app that gave its widget tree
  /// `Flutwire.builder`.
  bool get canDock => _hosts > 0;

  /// Whether the user last left the inspector docked, which makes it open
  /// docked again.
  bool get prefersDock => _prefersDock;

  /// Whether the inspector should open in the panel rather than full screen.
  bool get wantsDock => _prefersDock && canDock;

  /// The share of the screen the panel takes, along the side it is on.
  double get extent => _extent;

  /// The side the panel was last laid out on.
  FlutwireDockSide get side => _resolved;

  /// Whether the last screen the panel was laid out on has room for it beside
  /// the app.
  bool get canSitBeside => _screenWidth >= besideFrom;

  /// The side for a screen of [size]: the one the user chose, or by the shape of
  /// the screen, and always the bottom when the screen is too narrow for the
  /// panel to sit beside the app.
  FlutwireDockSide sideFor(Size size) {
    _screenWidth = size.width;
    if (!canSitBeside) return _resolved = FlutwireDockSide.bottom;
    return _resolved =
        _side ??
        (size.width >= wideFrom
            ? FlutwireDockSide.right
            : FlutwireDockSide.bottom);
  }

  /// Says that a widget tree that can show the panel is there. Hands back what
  /// takes it away again.
  VoidCallback attachHost() {
    _hosts++;
    var attached = true;
    return () {
      if (!attached) return;
      attached = false;
      if (--_hosts == 0) _isOpen = false;
    };
  }

  /// Shows the panel, and makes it where the inspector opens from now on. Does
  /// nothing while there is no widget tree to show it in.
  void open() {
    if (!canDock || _isOpen) return;
    _isOpen = true;
    _remember(docked: true);
    notifyListeners();
  }

  /// Hides the panel. The inspector still opens docked the next time.
  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }

  /// Hides the panel and makes the inspector open full screen the next time.
  void leave() {
    _isOpen = false;
    _remember(docked: false);
    notifyListeners();
  }

  /// Moves the panel to the other side of the app. Does nothing where the
  /// screen has no room for it beside the app.
  void swapSide() {
    if (_resolved == FlutwireDockSide.bottom && !canSitBeside) return;
    _side = _resolved == FlutwireDockSide.right
        ? FlutwireDockSide.bottom
        : FlutwireDockSide.right;
    _resolved = _side!;
    unawaited(_preferences?.write(_sideKey, _side!.name));
    notifyListeners();
  }

  /// Makes the panel [share] of the screen bigger, or smaller for a negative
  /// one, within the limits. It is kept once [keepSize] says the drag is over.
  void resizeBy(double share) {
    final next = (_extent + share).clamp(minExtent, maxExtent);
    if (next == _extent) return;
    _extent = next;
    notifyListeners();
  }

  /// Keeps the size the panel has now.
  void keepSize() =>
      unawaited(_preferences?.write(_extentKey, _extent.toStringAsFixed(3)));

  void _remember({required bool docked}) {
    _prefersDock = docked;
    unawaited(_preferences?.write(_modeKey, docked ? _dockedValue : null));
  }

  static FlutwireDockSide? _readSide(FlutwirePreferences? preferences) =>
      FlutwireDockSide.values.asNameMap()[preferences?.read(_sideKey)];

  static double _readExtent(FlutwirePreferences? preferences) {
    final stored = double.tryParse(preferences?.read(_extentKey) ?? '');
    return stored == null ? defaultExtent : stored.clamp(minExtent, maxExtent);
  }
}
