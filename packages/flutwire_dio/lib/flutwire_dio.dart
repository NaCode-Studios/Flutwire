/// A Dio interceptor for Flutwire.
///
/// Most apps do not need it: `Flutwire.init` already records every call made
/// through `dart:io`, which includes Dio's default adapter. Add it for the web,
/// where there is no `dart:io`, and for Dio adapters with a transport of their
/// own.
library;

export 'src/interceptor.dart' show FlutwireDioInterceptor;
