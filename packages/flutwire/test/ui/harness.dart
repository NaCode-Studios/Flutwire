import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/l10n/strings.dart';
import 'package:flutwire/src/l10n/strings_en.dart';
import 'package:flutwire/src/session.dart';
import 'package:flutwire/src/ui/scope.dart';
import 'package:flutwire/src/ui/theme/theme.dart';
import 'package:flutwire/src/ui/theme/tokens.dart';

import 'fake_session.dart';

/// Pumps [child] the way the inspector shows it: inside the Flutwire theme and
/// scope, in a [Scaffold], at [size] logical pixels. The screens work on
/// [session], or on an empty [FakeSession].
Future<void> pumpFlutwire(
  WidgetTester tester,
  Widget child, {
  FlutwireTokens tokens = FlutwireTokens.dark,
  FlutwireStrings strings = const FlutwireStringsEn(),
  FlutwireSession? session,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: flutwireTheme(tokens),
      debugShowCheckedModeBanner: false,
      home: FlutwireScope(
        session: session ?? FakeSession(),
        strings: strings,
        child: Scaffold(body: SafeArea(child: child)),
      ),
    ),
  );
  await tester.pump();
}
