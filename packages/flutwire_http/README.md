# flutwire_http

A `package:http` client for [Flutwire](https://pub.dev/packages/flutwire), the network inspector that opens from the notification shade.

Most apps do not need it. `Flutwire.init` already records every call made through `dart:io`, and that includes `package:http` on mobile and desktop. Use this package on the web, where there is no `dart:io`, and with clients that have a transport of their own, such as `cronet_http` or `cupertino_http`.

## Usage

```bash
flutter pub add flutwire_http
```

```dart
final client = FlutwireClient(http.Client());
```

Chopper uses an `http` client, so `ChopperClient(client: FlutwireClient(http.Client()))` covers it too.

Where the `dart:io` capture is installed, which is the default outside the web, the client stands down: the capture already sees the call with the bytes that went over the wire, and recording it twice would only fill the list. A client whose transport does not use `dart:io` needs `FlutwireClient(inner, force: true)`, because the capture cannot see it. If the client stands down for a call the capture never saw, the inspector names the client above the list.

## What it records

The request body of a `Request` and the response as it streams past, untouched and at the same pace. A `MultipartRequest` is described by its fields and files rather than reproduced byte for byte, because its body can be read only once, by the client that sends it.
