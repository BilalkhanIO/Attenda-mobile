/// Local by default so a development build can never silently write to the
/// production organization. Set API_URL explicitly for emulator/device targets
/// and every release build.
const apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:5000/api/v1',
);

/// A safe diagnostic that identifies the selected API host without logging
/// credentials, path segments, query parameters, or tokens.
String get apiBaseUrlTarget {
  final uri = Uri.tryParse(apiBaseUrl);
  if (uri == null || !uri.hasAuthority) return 'invalid API_URL';
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}
