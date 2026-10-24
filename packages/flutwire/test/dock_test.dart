import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/dock.dart';

void main() {
  group('a dock with nothing to dock into', () {
    test('cannot be opened', () {
      final dock = FlutwireDock();

      dock.open();

      expect(dock.canDock, isFalse);
      expect(dock.isOpen, isFalse);
      expect(dock.wantsDock, isFalse);
    });

    test('has the size it starts with', () {
      expect(FlutwireDock().extent, FlutwireDock.defaultExtent);
    });
  });

  group('a dock with a widget tree to show it in', () {
    late FlutwireDock dock;
    late VoidCallback detach;

    setUp(() {
      dock = FlutwireDock();
      detach = dock.attachHost();
    });

    test('opens, closes and says so', () {
      var told = 0;
      dock.addListener(() => told++);

      dock.open();
      expect(dock.isOpen, isTrue);
      dock.close();
      expect(dock.isOpen, isFalse);

      expect(told, 2);
    });

    test(
      'opens docked again after it was closed, but not after it was left',
      () {
        dock.open();
        dock.close();
        expect(dock.wantsDock, isTrue);

        dock.leave();
        expect(dock.wantsDock, isFalse);
        expect(dock.isOpen, isFalse);
      },
    );

    test('says nothing for what changes nothing', () {
      dock.open();
      var told = 0;
      dock.addListener(() => told++);

      dock.open();
      dock.resizeBy(0);

      expect(told, 0);
    });

    test('chooses the side by the shape of the screen', () {
      expect(dock.sideFor(const Size(1280, 800)), FlutwireDockSide.right);
      expect(dock.sideFor(const Size(420, 900)), FlutwireDockSide.bottom);
      expect(dock.side, FlutwireDockSide.bottom);
    });

    test('moves to the other side when asked, and then keeps it there', () {
      dock.sideFor(const Size(420, 900));

      dock.swapSide();
      expect(dock.sideFor(const Size(420, 900)), FlutwireDockSide.right);
      dock.swapSide();
      expect(dock.sideFor(const Size(1280, 800)), FlutwireDockSide.bottom);
    });

    test('is resized within limits', () {
      dock.resizeBy(1);
      expect(dock.extent, FlutwireDock.maxExtent);

      dock.resizeBy(-2);
      expect(dock.extent, FlutwireDock.minExtent);

      dock.resizeBy(0.1);
      expect(dock.extent, closeTo(FlutwireDock.minExtent + 0.1, 1e-9));
    });

    test('closes when the last widget tree that showed it goes', () {
      dock.open();

      detach();

      expect(dock.canDock, isFalse);
      expect(dock.isOpen, isFalse);
    });

    test('stays usable while another widget tree is still there', () {
      final other = dock.attachHost();
      dock.open();

      detach();
      detach();

      expect(dock.canDock, isTrue);
      expect(dock.isOpen, isTrue);
      other();
      expect(dock.canDock, isFalse);
    });
  });

  group('the choices of the user', () {
    test('are kept next to the history', () async {
      final preferences = MemoryFlutwirePreferences();
      final dock = FlutwireDock(preferences);
      dock.attachHost();

      dock.open();
      dock.swapSide();
      dock.resizeBy(0.1);
      dock.keepSize();

      expect(preferences.read('dockMode'), 'docked');
      expect(preferences.read('dockSide'), 'right');
      expect(
        double.parse(preferences.read('dockExtent')!),
        closeTo(0.52, 1e-9),
      );
    });

    test('are read when the next run starts', () {
      final dock = FlutwireDock(
        MemoryFlutwirePreferences({
          'dockMode': 'docked',
          'dockSide': 'right',
          'dockExtent': '0.55',
        }),
      );
      dock.attachHost();

      expect(dock.prefersDock, isTrue);
      expect(dock.wantsDock, isTrue);
      expect(dock.isOpen, isFalse);
      expect(dock.extent, 0.55);
      expect(dock.sideFor(const Size(420, 900)), FlutwireDockSide.right);
    });

    test('forget the dock once the inspector is left full screen', () {
      final preferences = MemoryFlutwirePreferences({'dockMode': 'docked'});
      final dock = FlutwireDock(preferences)..attachHost();

      dock.leave();

      expect(preferences.read('dockMode'), isNull);
    });

    test('are ignored when they make no sense', () {
      final dock = FlutwireDock(
        MemoryFlutwirePreferences({
          'dockSide': 'top',
          'dockExtent': 'wide',
          'dockMode': 'floating',
        }),
      );

      expect(dock.extent, FlutwireDock.defaultExtent);
      expect(dock.prefersDock, isFalse);
      expect(dock.sideFor(const Size(1280, 800)), FlutwireDockSide.right);
    });

    test('keep the size inside the limits', () {
      final dock = FlutwireDock(MemoryFlutwirePreferences({'dockExtent': '9'}));

      expect(dock.extent, FlutwireDock.maxExtent);
    });
  });
}
