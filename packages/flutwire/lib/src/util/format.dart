/// A byte count as people read it: `512 B`, `1.5 KB`, `3.2 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// A duration as people read it: `85 ms`, `1.24 s`, `2 min 5 s`.
String formatDuration(Duration duration) {
  final ms = duration.inMilliseconds;
  if (ms < 1000) return '$ms ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(2)} s';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds - minutes * 60;
  return '$minutes min $seconds s';
}

/// The standard reason phrase for [statusCode], or an empty string.
///
/// HTTP/2 has no reason phrase on the wire, so a response often arrives
/// without one and the inspector fills it in.
String reasonPhraseFor(int statusCode) => _phrases[statusCode] ?? '';

const Map<int, String> _phrases = {
  100: 'Continue',
  101: 'Switching Protocols',
  200: 'OK',
  201: 'Created',
  202: 'Accepted',
  204: 'No Content',
  206: 'Partial Content',
  301: 'Moved Permanently',
  302: 'Found',
  303: 'See Other',
  304: 'Not Modified',
  307: 'Temporary Redirect',
  308: 'Permanent Redirect',
  400: 'Bad Request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not Found',
  405: 'Method Not Allowed',
  406: 'Not Acceptable',
  408: 'Request Timeout',
  409: 'Conflict',
  410: 'Gone',
  412: 'Precondition Failed',
  413: 'Payload Too Large',
  415: 'Unsupported Media Type',
  418: "I'm a teapot",
  422: 'Unprocessable Entity',
  423: 'Locked',
  429: 'Too Many Requests',
  431: 'Request Header Fields Too Large',
  451: 'Unavailable For Legal Reasons',
  500: 'Internal Server Error',
  501: 'Not Implemented',
  502: 'Bad Gateway',
  503: 'Service Unavailable',
  504: 'Gateway Timeout',
};

/// How long before [now] [time] was, in the shortest honest words: `now`,
/// `12s`, `4m`, `3h`, and from a day on the date itself.
String formatAgo(DateTime time, DateTime now) {
  final gap = now.difference(time);
  if (gap.inSeconds < 3) return 'now';
  if (gap.inSeconds < 60) return '${gap.inSeconds}s';
  if (gap.inMinutes < 60) return '${gap.inMinutes}m';
  if (gap.inHours < 24) return '${gap.inHours}h';
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// A clock time with milliseconds, in the device's time zone: `12:04:31.482`.
String formatClock(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}

/// A date and a clock time: `2026-10-23 12:04:31.482`.
String formatDateTime(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${formatClock(time)}';
}
