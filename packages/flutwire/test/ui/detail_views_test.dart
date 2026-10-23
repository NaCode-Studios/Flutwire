import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/model/cookies.dart';
import 'package:flutwire/src/model/headers.dart';
import 'package:flutwire/src/ui/detail/cookies_view.dart';
import 'package:flutwire/src/ui/detail/headers_view.dart';

import 'body/helpers.dart';
import 'harness.dart';

void main() {
  group('the cookies view', () {
    testWidgets('says so when there are none', (tester) async {
      await pumpFlutwire(tester, const CookiesView(cookies: []));

      expect(find.text('No cookies'), findsOneWidget);
    });

    testWidgets('lists each cookie with its value and attributes', (
      tester,
    ) async {
      await pumpFlutwire(
        tester,
        CookiesView(
          cookies: [
            const FlutwireCookie(
              name: 'session',
              value: 'abc123',
              path: '/',
              httpOnly: true,
              secure: true,
            ),
            const FlutwireCookie(name: 'theme', value: 'dark'),
          ],
        ),
      );

      expect(find.text('session'), findsOneWidget);
      expect(find.text('abc123'), findsOneWidget);
      expect(find.text('Path=/'), findsOneWidget);
      expect(find.text('HttpOnly'), findsOneWidget);
      expect(find.text('Secure'), findsOneWidget);
      expect(find.text('theme'), findsOneWidget);
      expect(find.text('dark'), findsOneWidget);
    });

    testWidgets('copies a cookie as name=value when it is tapped', (
      tester,
    ) async {
      final clipboard = spyOnClipboard(tester);
      await pumpFlutwire(
        tester,
        const CookiesView(
          cookies: [FlutwireCookie(name: 'session', value: 'abc123')],
        ),
      );

      await tester.tap(find.text('session'));
      await tester.pump();

      expect(clipboard.last, 'session=abc123');
      expect(find.text('Copied'), findsOneWidget);
    });
  });

  group('the headers view', () {
    FlutwireHeaders headers() => FlutwireHeaders.fromMap({
      'content-type': 'application/json',
      'authorization': '[redacted]',
      'x-request-id': 'abc',
    });

    testWidgets('says so when there are none', (tester) async {
      await pumpFlutwire(
        tester,
        const HeadersView(headers: FlutwireHeaders.empty),
      );

      expect(find.text('No header fields'), findsOneWidget);
    });

    testWidgets('lists each field with its value, and how many there are', (
      tester,
    ) async {
      await pumpFlutwire(tester, HeadersView(headers: headers()));

      expect(find.text('3'), findsOneWidget);
      expect(find.text('content-type'), findsOneWidget);
      expect(find.text('application/json'), findsOneWidget);
      expect(find.text('x-request-id'), findsOneWidget);
    });

    testWidgets('shows a hidden value as hidden, not as the mask', (
      tester,
    ) async {
      await pumpFlutwire(tester, HeadersView(headers: headers()));

      expect(find.text('authorization'), findsOneWidget);
      expect(find.text('Hidden'), findsOneWidget);
      expect(find.text('[redacted]'), findsNothing);
    });

    testWidgets('copies a field when it is tapped', (tester) async {
      final clipboard = spyOnClipboard(tester);
      await pumpFlutwire(tester, HeadersView(headers: headers()));

      await tester.tap(find.text('x-request-id'));
      await tester.pump();

      expect(clipboard.last, 'x-request-id: abc');
    });

    testWidgets('copies every field with the Copy button', (tester) async {
      final clipboard = spyOnClipboard(tester);
      await pumpFlutwire(tester, HeadersView(headers: headers()));

      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(
        clipboard.last,
        'content-type: application/json\n'
        'authorization: [redacted]\n'
        'x-request-id: abc',
      );
    });
  });
}
