import '../coverage.dart' show FlutwireGap;
import '../model/message.dart' show FlutwireMessageKind;
import 'strings.dart';

/// English.
class FlutwireStringsEn extends FlutwireStrings {
  /// Creates the English strings.
  const FlutwireStringsEn();

  @override
  String get channelName => 'Network activity';

  @override
  String get channelDescription =>
      'A summary of the HTTP calls your app makes.';

  @override
  String get notificationTitle => 'Recording network activity';

  @override
  String get clear => 'Clear';

  @override
  String get shortcutLabel => 'Open Flutwire';

  @override
  String summary({required int calls, required int failed}) {
    final base = calls == 1 ? '1 call' : '$calls calls';
    return failed == 0 ? base : '$base · $failed failed';
  }

  @override
  String get inspectorTitle => 'Network activity';

  @override
  String get close => 'Close';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get share => 'Share';

  @override
  String get save => 'Save';

  @override
  String get search => 'Search';

  @override
  String get settings => 'Settings';

  @override
  String get pin => 'Pin';

  @override
  String get unpin => 'Unpin';

  @override
  String get searchHint => 'Search URL, status, headers or body';

  @override
  String get filters => 'Filters';

  @override
  String get filterSuccess => '2xx';

  @override
  String get filterRedirect => '3xx';

  @override
  String get filterClientError => '4xx';

  @override
  String get filterServerError => '5xx';

  @override
  String get filterFailed => 'Failed';

  @override
  String get filterRunning => 'Running';

  @override
  String get filterPinned => 'Pinned';

  @override
  String get filterOtherMethods => 'Other';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get sortNewest => 'Newest first';

  @override
  String get sortSlowest => 'Slowest first';

  @override
  String get sortLargest => 'Largest first';

  @override
  String get sortBy => 'Sort by';

  @override
  String get statCalls => 'Calls';

  @override
  String get statFailed => 'Failed';

  @override
  String get statAverage => 'Average';

  @override
  String get statTransferred => 'Transferred';

  @override
  String get emptyTitle => 'Nothing recorded yet';

  @override
  String get emptyBody =>
      'The calls your app makes appear here as they happen, and in the notification.';

  @override
  String get emptyFiltered => 'No call matches';

  @override
  String get searchingBodies => 'Searching the bodies';

  @override
  String get pickACall => 'Pick a call to read it';

  @override
  String get recording => 'Recording';

  @override
  String get paused => 'Paused';

  @override
  String get pauseRecording => 'Pause recording';

  @override
  String get resumeRecording => 'Resume recording';

  @override
  String get exportAll => 'Export all';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get clearHistoryTitle => 'Clear the history?';

  @override
  String clearHistoryBody(int calls) => calls == 1
      ? 'The recorded call will be removed. Pinned calls stay.'
      : 'The $calls recorded calls will be removed. Pinned calls stay.';

  @override
  String selected(int count) => '$count selected';

  @override
  String get selectAll => 'Select all';

  @override
  String get deleteSelectedTitle => 'Delete the selected calls?';

  @override
  String get running => 'Running';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get failed => 'Failed';

  @override
  String get tabOverview => 'Overview';

  @override
  String get tabRequest => 'Request';

  @override
  String get tabResponse => 'Response';

  @override
  String get tabBody => 'Body';

  @override
  String get tabHeaders => 'Headers';

  @override
  String get tabCookies => 'Cookies';

  @override
  String get url => 'URL';

  @override
  String get method => 'Method';

  @override
  String get status => 'Status';

  @override
  String get source => 'Recorded by';

  @override
  String get remote => 'Server';

  @override
  String get certificate => 'Certificate';

  @override
  String get started => 'Started';

  @override
  String get duration => 'Duration';

  @override
  String get firstByte => 'First byte';

  @override
  String get requestSize => 'Request size';

  @override
  String get responseSize => 'Response size';

  @override
  String get redirects => 'Redirects';

  @override
  String get graphql => 'GraphQL';

  @override
  String get error => 'Error';

  @override
  String get compression => 'Compression';

  @override
  String get noHeaders => 'No header fields';

  @override
  String get noCookies => 'No cookies';

  @override
  String get redacted => 'Hidden';

  @override
  String get noResponseYet => 'No response yet';

  @override
  String get copyUrl => 'Copy URL';

  @override
  String get copyCurl => 'Copy as cURL';

  @override
  String get shareAsText => 'Share as text';

  @override
  String get shareAsCurl => 'Share as cURL';

  @override
  String get shareAsHar => 'Share as HAR';

  @override
  String get shareAsJson => 'Share as JSON';

  @override
  String get callGone => 'This call is no longer in the history';

  @override
  String get notificationSetting => 'Notification';

  @override
  String get notificationOn => 'Showing the latest calls in the shade';

  @override
  String get notificationDenied => 'Notifications are turned off for this app';

  @override
  String get notificationUnsupported => 'This platform has no notification';

  @override
  String get allowNotifications => 'Allow notifications';

  @override
  String get openSystemSettings => 'Open system settings';

  @override
  String get appearanceSetting => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get retentionSetting => 'Keep history for';

  @override
  String get retentionHour => '1 hour';

  @override
  String get retentionDay => '1 day';

  @override
  String get retentionWeek => '1 week';

  @override
  String get retentionForever => 'Forever';

  @override
  String get appliesOnRestart => 'Applies the next time the app starts';

  @override
  String get about => 'About';

  @override
  String get bodyEmpty => 'No body';

  @override
  String get bodyNotLoaded => 'The body could not be read from the history';

  @override
  String bodyBinary(String size, String type) =>
      'Binary data, $size${type.isEmpty ? '' : ', $type'}';

  @override
  String bodyTruncated(String kept, String total) =>
      'Showing the first $kept of $total';

  @override
  String bodyDecodedBy(String name) => 'Decoded as $name';

  @override
  String get showRaw => 'Show raw';

  @override
  String get showDecoded => 'Show decoded';

  @override
  String get viewTree => 'Tree';

  @override
  String get viewPretty => 'Pretty';

  @override
  String get viewRaw => 'Raw';

  @override
  String get viewHex => 'Hex';

  @override
  String get viewFields => 'Fields';

  @override
  String get viewParts => 'Parts';

  @override
  String get viewPreview => 'Preview';

  @override
  String get wrapLines => 'Wrap lines';

  @override
  String get lineNumbers => 'Line numbers';

  @override
  String get searchInBody => 'Search in the body';

  @override
  String get noMatches => 'No matches';

  @override
  String matchCounter(int index, int total) => '$index of $total';

  @override
  String get previousMatch => 'Previous match';

  @override
  String get nextMatch => 'Next match';

  @override
  String get copyBody => 'Copy body';

  @override
  String get copyFormatted => 'Copy formatted';

  @override
  String get copyRaw => 'Copy raw';

  @override
  String get saveBody => 'Save body to a file';

  @override
  String get expandAll => 'Expand all';

  @override
  String get collapseAll => 'Collapse all';

  @override
  String get copyValue => 'Copy value';

  @override
  String get copyPath => 'Copy path';

  @override
  String itemsCount(int count) => count == 1 ? '1 item' : '$count items';

  @override
  String partsCount(int count) => count == 1 ? '1 part' : '$count parts';

  @override
  String imageSize(int width, int height) => '$width × $height px';

  @override
  String get imageFailed => 'This image could not be drawn';

  @override
  String get filePart => 'File';

  @override
  String get showMore => 'Show more';

  // Body viewer additions

  @override
  String get viewDecoded => 'Decoded';

  @override
  String get showLess => 'Show less';

  @override
  String matchCounterCapped(int index, int total) {
    final grouped = '$total'.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$index of $grouped+';
  }

  @override
  String get saveFormatted => 'Save formatted';

  @override
  String get saveFailed => 'Could not share this file';

  @override
  String get moreActions => 'More actions';

  @override
  String get coverageBanner => 'Flutwire may be missing calls';

  @override
  String get coverageDetails => 'Details';

  @override
  String get coverageTitle => 'What Flutwire may not see';

  @override
  String coverageGapTitle(FlutwireGap gap) => switch (gap) {
    FlutwireGap.clientBypassesDartIo => 'A client that does not use dart:io',
    FlutwireGap.captureReplaced => 'The dart:io capture was replaced',
    FlutwireGap.otherIsolate => 'A call from another isolate',
  };

  @override
  String coverageGapWhat(FlutwireGap gap, String subject) => switch (gap) {
    FlutwireGap.clientBypassesDartIo =>
      '$subject made a call that the dart:io capture never saw. The adapter '
          'stood down for it, so the call is not in the list.',
    FlutwireGap.captureReplaced =>
      'Something set HttpOverrides.global without chaining to the override '
          'Flutwire installed, so calls through dart:io are no longer '
          'recorded.',
    FlutwireGap.otherIsolate =>
      '$subject. Nothing records in this isolate until it attaches to '
          'Flutwire, so its calls are not in the list.',
  };

  @override
  String coverageGapFix(FlutwireGap gap) => switch (gap) {
    FlutwireGap.clientBypassesDartIo =>
      'Pass force: true to the adapter, so that it records the call itself.',
    FlutwireGap.captureReplaced =>
      'Set your own overrides before Flutwire.init, or build them on '
          'HttpOverrides.current.',
    FlutwireGap.otherIsolate =>
      'Run it with Flutwire.run or Flutwire.compute, or call '
          'Flutwire.attach() first thing in the isolate.',
  };

  @override
  String coverageSeen(int count) =>
      count == 1 ? 'Seen once' : 'Seen $count times';

  @override
  String get resend => 'Edit and resend';

  @override
  String get send => 'Send';

  @override
  String get sending => 'Sending';

  @override
  String get addHeader => 'Add header';

  @override
  String get headerName => 'Name';

  @override
  String get headerValue => 'Value';

  @override
  String get removeHeader => 'Remove header';

  @override
  String get hiddenValue => 'Hidden';

  @override
  String resendTarget(String host) => 'Sends a real request to $host.';

  @override
  String resendHiddenNote(String names) =>
      'Not sent, because Flutwire hid their values when it recorded the call: '
      '$names. Type a value to send one.';

  @override
  String resendBodyCut(String kept, String total) =>
      'The body was cut at $kept of $total. This is only the start of it.';

  @override
  String resendBinaryBody(String size) =>
      'A body that is not text, $size. It is sent as it was recorded.';

  @override
  String get resendBinaryCut =>
      'Only part of this body was recorded, so it is not sent.';

  @override
  String get resendSendBody => 'Send the recorded body';

  @override
  String resendBodyHidden(String mask) =>
      'Some values in the body were hidden when the call was recorded and show '
      'as $mask. Replace them to send the real ones.';

  @override
  String resendUrlHidden(String mask) =>
      'A value in the address was hidden when the call was recorded and shows '
      'as $mask. Replace it to send the real one.';

  @override
  String get resendBadUrl =>
      'Enter a full address, such as https://example.com/path.';

  @override
  String get resendNotRecorded => 'Sent, but Flutwire could not record it.';

  @override
  String get resendFailed => 'The request could not be sent.';

  @override
  String get resentFrom => 'Sent again from';

  @override
  String get resentFromGone => 'A call that is no longer in the history';

  @override
  String get resentBadge => 'Sent again';

  @override
  String get tabMessages => 'Messages';

  @override
  String get tabEvents => 'Events';

  @override
  String messageCount(int count) =>
      count == 1 ? '1 message' : '$count messages';

  @override
  String eventCount(int count) => count == 1 ? '1 event' : '$count events';

  @override
  String get messagesAll => 'All';

  @override
  String get messagesSent => 'Sent';

  @override
  String get messagesReceived => 'Received';

  @override
  String messagesDropped(int count) => count == 1
      ? 'One earlier message was not kept.'
      : '$count earlier messages were not kept.';

  @override
  String get messagesEmpty => 'Nothing has crossed yet';

  @override
  String messageKind(FlutwireMessageKind kind) => switch (kind) {
    FlutwireMessageKind.text => 'Text',
    FlutwireMessageKind.binary => 'Binary',
    FlutwireMessageKind.ping => 'Ping',
    FlutwireMessageKind.pong => 'Pong',
    FlutwireMessageKind.close => 'Close',
    FlutwireMessageKind.event => 'Event',
  };

  @override
  String get messageNoPayload => 'No payload';

  @override
  String get messageUndecoded =>
      'This message was compressed and could not be decompressed, so its '
      'bytes are shown as they came.';

  @override
  String get compare => 'Compare';

  @override
  String get compareSwap => 'Swap sides';

  @override
  String get compareDifferencesOnly => 'Differences only';

  @override
  String get compareIdentical => 'Identical';

  @override
  String compareDifferences(int count) =>
      count == 1 ? '1 difference' : '$count differences';

  @override
  String get compareHost => 'Host';

  @override
  String get comparePath => 'Path';

  @override
  String get compareQuery => 'Query parameters';

  @override
  String get compareRequestHeaders => 'Request headers';

  @override
  String get compareResponseHeaders => 'Response headers';

  @override
  String get compareRequestBody => 'Request body';

  @override
  String get compareResponseBody => 'Response body';

  @override
  String get compareMissing => 'Missing';

  @override
  String compareSkipped(int lines) =>
      lines == 1 ? '1 identical line' : '$lines identical lines';

  @override
  String compareBinarySame(String size) => 'Same bytes ($size)';

  @override
  String compareBinaryDiffer(String left, String right) =>
      'Different bytes: $left against $right';

  @override
  String compareCut(String side, String kept, String total) =>
      'Side $side is cut: $kept of $total shown.';

  @override
  String get compareWithOriginal => 'Compare with the original';

  @override
  String get statistics => 'Statistics';

  @override
  String get statsSummary => 'Summary';

  @override
  String get statsTimeline => 'Timeline';

  @override
  String get statsErrorRate => 'Error rate';

  @override
  String get statsMedian => 'Median';

  @override
  String get statsP95 => '95th percentile';

  @override
  String get statsSlowest => 'Slowest calls';

  @override
  String get statsHosts => 'Error rate by host';

  @override
  String statsHostLine(int calls, int failed) =>
      '${calls == 1 ? '1 call' : '$calls calls'}, $failed failed';

  @override
  String statsMoreHosts(int count) => '$count more hosts';

  @override
  String get statsNoHost => '(no host)';

  @override
  String statsPeak(int count) =>
      count <= 1 ? 'One at a time' : 'Up to $count at once';

  @override
  String statsShowingLatest(int shown, int total) =>
      'The latest $shown of $total calls';

  @override
  String get statsWaiting => 'Waiting';

  @override
  String get statsReceiving => 'Receiving';

  @override
  String get dockInspector => 'Dock beside the app';

  @override
  String get undockInspector => 'Open full screen';

  @override
  String get dockToBottom => 'Move to the bottom';

  @override
  String get dockToRight => 'Move to the right';

  @override
  String get dockResize => 'Resize the inspector';

  @override
  String get interceptTitle => 'Mocks and breakpoints';

  @override
  String get interceptOffBody =>
      'Mocks and breakpoints change what the app sends and receives, so they '
      'stay off until the app turns them on.';

  @override
  String get interceptOffHow => 'Turn them on when Flutwire starts:';

  @override
  String get interceptUnavailableBody =>
      'They work through the dart:io capture, and this app has none: it runs '
      'on the web, or captureDartIo is off.';

  @override
  String get interceptEmptyTitle => 'No rules yet';

  @override
  String get interceptEmptyBody =>
      'Open a call and choose "Mock this response" or "Break on requests '
      'like this", or add a rule here.';

  @override
  String get interceptNewMock => 'New mock';

  @override
  String get interceptNewBreakpoint => 'New breakpoint';

  @override
  String get interceptMock => 'Mock';

  @override
  String get interceptBreakpoint => 'Breakpoint';

  @override
  String interceptRulesActive(int count) =>
      count == 1 ? '1 rule in force' : '$count rules in force';

  @override
  String get ruleDelete => 'Delete the rule';

  @override
  String get ruleDeleteTitle => 'Delete this rule?';

  @override
  String get ruleEditMock => 'Mock';

  @override
  String get ruleEditBreakpoint => 'Breakpoint';

  @override
  String get rulePattern => 'Address';

  @override
  String get rulePatternHelp =>
      'Use * for any run of characters, as in api.test/items/*. Without a '
      'scheme it matches the host and the path.';

  @override
  String get rulePatternBad => 'Write what the address looks like.';

  @override
  String get ruleMethodAny => 'Any method';

  @override
  String get ruleName => 'Name (optional)';

  @override
  String get ruleStatus => 'Status code';

  @override
  String get ruleStatusBad => 'A status is a number from 100 to 599.';

  @override
  String get ruleDelay => 'Delay in milliseconds';

  @override
  String get ruleBodyNotText =>
      'The stored body is not text, so it is served as it was recorded.';

  @override
  String get heldTitle => 'Held request';

  @override
  String get heldNote =>
      'This request is held at a breakpoint and the app is waiting for it. '
      'Change what you like and send it on, or stop it.';

  @override
  String get heldStop => 'Stop the request';

  @override
  String get heldGone => 'This request is not held any more.';

  @override
  String heldBanner(int count) => count == 1
      ? '1 request is held at a breakpoint'
      : '$count requests are held at a breakpoint';

  @override
  String get heldReview => 'Review';

  @override
  String get mockThisResponse => 'Mock this response';

  @override
  String get breakOnThis => 'Break on requests like this';

  @override
  String get badgeMocked => 'MOCK';

  @override
  String get badgeEdited => 'EDITED';

  @override
  String get badgeHeld => 'HELD';

  @override
  String get interceptFact => 'Intercepted';

  @override
  String get interceptedMocked =>
      'Answered by a mock rule, and nothing was sent';

  @override
  String get interceptedEdited => 'Held at a breakpoint and sent with changes';

  @override
  String get interceptedHeld => 'Held at a breakpoint';
}
