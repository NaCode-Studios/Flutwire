# flutwire_dio

A Dio interceptor for [Flutwire](https://pub.dev/packages/flutwire), the network inspector that opens from the notification shade.

Most apps do not need it. `Flutwire.init` already records every call made through `dart:io`, and that includes Dio's default adapter. Add this package for the web, where there is no `dart:io`, and for Dio adapters with a transport of their own.

## Usage

```bash
flutter pub add flutwire_dio
```

```dart
final dio = Dio()..interceptors.add(FlutwireDioInterceptor());
```

Add it last, so that it sees the headers the other interceptors added.

Where the `dart:io` capture is installed, which is the default outside the web, the interceptor stands down: the capture already sees the call with the bytes that went over the wire, and recording it twice would only fill the list. Pass `force: true` to record anyway.

## What it records

The call as Dio sees it: the request data before the transformer encodes it, and the response data after the transformer decoded it. A `FormData` body is described by its fields and files rather than reproduced byte for byte. A response read as a stream is not recorded, because reading it would consume it.
