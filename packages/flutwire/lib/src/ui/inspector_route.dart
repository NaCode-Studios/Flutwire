import 'package:flutter/material.dart';

import '../flutwire.dart';

/// The route that shows the inspector.
Route<void> inspectorRoute() => MaterialPageRoute<void>(
  settings: const RouteSettings(name: 'flutwire'),
  builder: (_) => const _Placeholder(),
);

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutwire')),
      body: ValueListenableBuilder(
        valueListenable: Flutwire.calls,
        builder: (context, calls, _) => ListView(
          children: [
            for (final c in calls)
              ListTile(
                title: Text('${c.method} ${c.pathAndQuery}'),
                subtitle: Text('${c.statusCode ?? c.state.name}  ${c.host}'),
              ),
          ],
        ),
      ),
    );
  }
}
