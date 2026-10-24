import '../coverage.dart' show FlutwireGap;

/// Every piece of text Flutwire shows, in one language.
///
/// English and Italian ship with the package, and `stringsFor` picks one for a
/// locale. A new language is a subclass of this one and a line in that
/// function.
abstract class FlutwireStrings {
  /// Creates a set of strings.
  const FlutwireStrings();

  /// The name of the notification channel on Android.
  String get channelName;

  /// What the notification channel is for, shown in the system settings.
  String get channelDescription;

  /// The title of the notification in the shade.
  String get notificationTitle;

  /// The label of the notification's clear button.
  String get clear;

  /// The label of the app icon shortcut.
  String get shortcutLabel;

  /// A line summarising the history: how many calls and how many went wrong.
  String summary({required int calls, required int failed});

  // General

  /// The inspector's headline.
  String get inspectorTitle;

  /// Dismisses a screen.
  String get close;

  /// Backs out of a dialog.
  String get cancel;

  /// Removes something.
  String get delete;

  /// Copies text to the clipboard.
  String get copy;

  /// Confirms that something was copied.
  String get copied;

  /// Opens the share sheet.
  String get share;

  /// Writes something to a file.
  String get save;

  /// Opens or labels a search field.
  String get search;

  /// Opens the settings.
  String get settings;

  /// Keeps a call from being removed.
  String get pin;

  /// Lets a pinned call be removed again.
  String get unpin;

  // The list

  /// The placeholder of the search field.
  String get searchHint;

  /// The heading of the filter area.
  String get filters;

  /// A filter chip: successful calls.
  String get filterSuccess;

  /// A filter chip: redirects.
  String get filterRedirect;

  /// A filter chip: client errors.
  String get filterClientError;

  /// A filter chip: server errors.
  String get filterServerError;

  /// A filter chip: calls that failed with no response.
  String get filterFailed;

  /// A filter chip: calls still running.
  String get filterRunning;

  /// A filter chip: pinned calls.
  String get filterPinned;

  /// A filter chip: every other method.
  String get filterOtherMethods;

  /// Removes every filter.
  String get clearFilters;

  /// Sorts the newest call first.
  String get sortNewest;

  /// Sorts the slowest call first.
  String get sortSlowest;

  /// Sorts the biggest call first.
  String get sortLargest;

  /// The label of the sort menu.
  String get sortBy;

  /// The tile that counts calls.
  String get statCalls;

  /// The tile that counts calls that went wrong.
  String get statFailed;

  /// The tile with the average duration.
  String get statAverage;

  /// The tile with the bytes moved.
  String get statTransferred;

  /// The heading of the empty list.
  String get emptyTitle;

  /// What the empty list explains.
  String get emptyBody;

  /// What a list with filters but no match says.
  String get emptyFiltered;

  /// What the list says while the bodies are searched and nothing matched yet.
  String get searchingBodies;

  /// What the detail pane says while no call is open.
  String get pickACall;

  /// The badge of a recording inspector.
  String get recording;

  /// The badge of a paused inspector.
  String get paused;

  /// Pauses recording.
  String get pauseRecording;

  /// Resumes recording.
  String get resumeRecording;

  /// Exports the whole history.
  String get exportAll;

  /// Removes every call.
  String get clearHistory;

  /// The title of the dialog that confirms clearing.
  String get clearHistoryTitle;

  /// The body of the dialog that confirms clearing [calls] calls.
  String clearHistoryBody(int calls);

  /// The heading of a selection of [count] calls.
  String selected(int count);

  /// Selects every call in the list.
  String get selectAll;

  /// The title of the dialog that confirms deleting a selection.
  String get deleteSelectedTitle;

  /// A call that has not finished.
  String get running;

  /// A call that the app abandoned.
  String get cancelled;

  /// A call that never got a response.
  String get failed;

  // The detail

  /// The tab with the facts of a call.
  String get tabOverview;

  /// The tab with what was sent.
  String get tabRequest;

  /// The tab with what came back.
  String get tabResponse;

  /// The sub-tab with the body.
  String get tabBody;

  /// The sub-tab with the header fields.
  String get tabHeaders;

  /// The sub-tab with the cookies.
  String get tabCookies;

  /// The label of the URL.
  String get url;

  /// The label of the method.
  String get method;

  /// The label of the status.
  String get status;

  /// The label of where the call was recorded.
  String get source;

  /// The label of the server address.
  String get remote;

  /// The label of the certificate.
  String get certificate;

  /// The label of the start time.
  String get started;

  /// The label of the duration.
  String get duration;

  /// The label of the time to the first byte.
  String get firstByte;

  /// The label of the request size.
  String get requestSize;

  /// The label of the response size.
  String get responseSize;

  /// The label of the redirects followed.
  String get redirects;

  /// The label of the GraphQL operation.
  String get graphql;

  /// The label of an error.
  String get error;

  /// The label of the compression.
  String get compression;

  /// Says a call has no header fields.
  String get noHeaders;

  /// Says there are no cookies.
  String get noCookies;

  /// A header value that was hidden.
  String get redacted;

  /// Says the call has no response yet.
  String get noResponseYet;

  /// Copies the URL.
  String get copyUrl;

  /// Copies a cURL command.
  String get copyCurl;

  /// Shares one call as text.
  String get shareAsText;

  /// Shares one call as a cURL command.
  String get shareAsCurl;

  /// Shares one call as HAR.
  String get shareAsHar;

  /// Shares one call as JSON.
  String get shareAsJson;

  /// Says a call could not be read from the history.
  String get callGone;

  // Settings

  /// The label of the notification setting.
  String get notificationSetting;

  /// Says the notification is on.
  String get notificationOn;

  /// Says notifications were refused.
  String get notificationDenied;

  /// Says the platform has no notification.
  String get notificationUnsupported;

  /// Asks for notification permission.
  String get allowNotifications;

  /// Opens the system settings.
  String get openSystemSettings;

  /// The label of the look setting.
  String get appearanceSetting;

  /// Follows the device's light or dark setting.
  String get themeSystem;

  /// The light look.
  String get themeLight;

  /// The dark look.
  String get themeDark;

  /// The label of the retention setting.
  String get retentionSetting;

  /// One hour of retention.
  String get retentionHour;

  /// One day of retention.
  String get retentionDay;

  /// One week of retention.
  String get retentionWeek;

  /// No time limit.
  String get retentionForever;

  /// Explains that a setting applies on the next start.
  String get appliesOnRestart;

  /// The label of the about line.
  String get about;

  // The body viewer

  /// Says a body is empty.
  String get bodyEmpty;

  /// Says a body has not been read from disk.
  String get bodyNotLoaded;

  /// Says a body is binary, with its [size] and media [type].
  String bodyBinary(String size, String type);

  /// Says a body was cut: [kept] of [total].
  String bodyTruncated(String kept, String total);

  /// Says a body was decoded by a decoder called [name].
  String bodyDecodedBy(String name);

  /// Switches from the decoded text to the raw one.
  String get showRaw;

  /// Switches from the raw text to the decoded one.
  String get showDecoded;

  /// The tree view of JSON.
  String get viewTree;

  /// The indented view of text.
  String get viewPretty;

  /// The view of the bytes as they came.
  String get viewRaw;

  /// The hexadecimal view.
  String get viewHex;

  /// The view of form fields.
  String get viewFields;

  /// The view of multipart parts.
  String get viewParts;

  /// The view of an image.
  String get viewPreview;

  /// Wraps long lines.
  String get wrapLines;

  /// Shows line numbers.
  String get lineNumbers;

  /// The placeholder of the search in a body.
  String get searchInBody;

  /// Says a search found nothing.
  String get noMatches;

  /// Says the search is on match [index] of [total].
  String matchCounter(int index, int total);

  /// Goes to the previous match.
  String get previousMatch;

  /// Goes to the next match.
  String get nextMatch;

  /// Copies the body.
  String get copyBody;

  /// Copies the body indented.
  String get copyFormatted;

  /// Copies the body as it came.
  String get copyRaw;

  /// Saves the body to a file.
  String get saveBody;

  /// Opens every node of a tree.
  String get expandAll;

  /// Closes every node of a tree.
  String get collapseAll;

  /// Copies the value of a node.
  String get copyValue;

  /// Copies the path of a node.
  String get copyPath;

  /// Counts the items of a JSON array or object.
  String itemsCount(int count);

  /// Counts the parts of a multipart body.
  String partsCount(int count);

  /// Gives the size of an image in pixels.
  String imageSize(int width, int height);

  /// Says an image could not be drawn.
  String get imageFailed;

  /// Says a part of an upload is a file.
  String get filePart;

  /// Shows the rest of a long value.
  String get showMore;

  // Body viewer additions

  /// The view of text that a decoder produced.
  String get viewDecoded;

  /// Folds a long value back to its first part.
  String get showLess;

  /// Says the search is on match [index] of more than [total], because the
  /// search stops counting at a limit.
  String matchCounterCapped(int index, int total);

  /// Saves the body indented, or as a decoder showed it, to a file.
  String get saveFormatted;

  /// Says a body could not be handed to the system as a file.
  String get saveFailed;

  /// The label of a menu that holds the less common actions.
  String get moreActions;

  // Coverage

  /// The line above the list that says Flutwire may be missing calls.
  String get coverageBanner;

  /// The action that opens the reasons.
  String get coverageDetails;

  /// The title of the list of reasons.
  String get coverageTitle;

  /// The name of a blind spot.
  String coverageGapTitle(FlutwireGap gap);

  /// What happened, for a blind spot about [subject].
  String coverageGapWhat(FlutwireGap gap, String subject);

  /// What to do about a blind spot.
  String coverageGapFix(FlutwireGap gap);

  /// How often a blind spot was seen.
  String coverageSeen(int count);
}
