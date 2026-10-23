import 'package:flutter/material.dart';

import 'inspector/inspector_page.dart';
import 'shell.dart';

/// The route that shows the inspector.
Route<void> inspectorRoute() => MaterialPageRoute<void>(
  settings: const RouteSettings(name: 'flutwire'),
  builder: (_) => const FlutwireShell(child: InspectorPage()),
);
