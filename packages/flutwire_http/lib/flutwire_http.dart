/// A `package:http` client for Flutwire.
///
/// Most apps do not need it: `Flutwire.init` already records every call made
/// through `dart:io`, which includes `package:http` on mobile and desktop. Use
/// it on the web, where there is no `dart:io`, and with clients that have a
/// transport of their own. Chopper uses an `http` client, so
/// `ChopperClient(client: FlutwireClient(http.Client()))` covers it too.
library;

export 'src/client.dart';
