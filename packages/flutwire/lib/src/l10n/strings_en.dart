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
  String get inspectorTitle => 'Network';

  @override
  String get inspectorTitleAccent => 'activity';

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
  String get searchHint => 'Search path, host, status or body';

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
}
