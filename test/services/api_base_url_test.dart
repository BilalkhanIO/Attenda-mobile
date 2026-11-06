import 'package:flutter_test/flutter_test.dart';
import 'package:attenda/services/api_base_url.dart';

void main() {
  test('API target diagnostic contains only scheme and authority', () {
    expect(apiBaseUrlTarget, isNot(contains('@')));
    expect(apiBaseUrlTarget, isNot(contains('/api/')));
    expect(apiBaseUrlTarget, isNot(contains('?')));
    expect(apiBaseUrlTarget, isNot(contains('#')));
  });

  test('API URL cannot silently fall back to the production host', () {
    expect(
        apiBaseUrl, isNot(contains('attenda-api-production.up.railway.app')));
  });
}
