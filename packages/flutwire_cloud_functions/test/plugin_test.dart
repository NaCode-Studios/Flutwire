import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart'
    show FirebaseFunctionsPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire_cloud_functions/flutwire_cloud_functions.dart';

import 'fakes.dart';

/// The same wiring an app has: the real `cloud_functions` plugin and a real
/// `FirebaseApp`, with only the native end replaced.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String project;

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    project = Firebase.app().options.projectId;
  });

  setUp(() async {
    await Flutwire.init(
      config: const FlutwireConfig(
        enabled: true,
        persist: false,
        captureDartIo: false,
        shortcut: false,
        notification: FlutwireNotificationConfig(enabled: false),
      ),
    );
  });

  tearDown(() async {
    FlutwireCloudFunctions.uninstall();
    await Flutwire.reset();
  });

  List<FlutwireCall> recorded() {
    (Flutwire.store! as MemoryFlutwireStore).flush();
    return Flutwire.calls.value.reversed.toList();
  }

  // FirebaseFunctions caches one instance, and its platform, per region, so
  // each test uses a region of its own.
  test(
    'httpsCallable is recorded with the project of the Firebase app',
    () async {
      FirebaseFunctionsPlatform.instance = FakeFunctions((p) => {'ok': true});
      FlutwireCloudFunctions.install();

      final result = await FirebaseFunctions.instanceFor(
        region: 'europe-west1',
      ).httpsCallable('createClub').call<Object?>({'name': 'Orion'});

      expect(result.data, {'ok': true});
      final call = recorded().single;
      expect(
        call.uri.toString(),
        'https://europe-west1-$project.cloudfunctions.net/createClub',
      );
      expect(call.request.body.jsonValue, {
        'data': {'name': 'Orion'},
      });
      expect(call.response!.body.jsonValue, {
        'result': {'ok': true},
      });
    },
  );

  test('httpsCallableFromUrl is recorded at the URL it was given', () async {
    FirebaseFunctionsPlatform.instance = FakeFunctions((p) => 'done');
    FlutwireCloudFunctions.install();

    final result = await FirebaseFunctions.instanceFor(region: 'us-east1')
        .httpsCallableFromUrl('https://acceptclubdocuments-abc-ew.a.run.app')
        .call<Object?>();

    expect(result.data, 'done');
    expect(recorded().single.uri.host, 'acceptclubdocuments-abc-ew.a.run.app');
  });

  test(
    'an error comes out of the plugin as the exception the app expects',
    () async {
      FirebaseFunctionsPlatform.instance = FakeFunctions(
        (p) => throw FakeException('not-found', 'No such club'),
      );
      FlutwireCloudFunctions.install();

      await expectLater(
        FirebaseFunctions.instanceFor(
          region: 'asia-east1',
        ).httpsCallable('getClub').call<Object?>({'id': 'x'}),
        throwsA(
          isA<FirebaseFunctionsException>()
              .having((e) => e.code, 'code', 'not-found')
              .having((e) => e.message, 'message', 'No such club'),
        ),
      );

      expect(recorded().single.statusCode, 404);
    },
  );

  test('without the recording the same call is not in the history', () async {
    FirebaseFunctionsPlatform.instance = FakeFunctions((p) => 1);

    await FirebaseFunctions.instanceFor(
      region: 'southamerica-east1',
    ).httpsCallable('quiet').call<Object?>();

    expect(recorded(), isEmpty);
  });
}
