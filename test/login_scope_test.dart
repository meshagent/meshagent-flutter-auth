import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_auth/meshagent_flutter_auth.dart';

void main() {
  test('LoginScope defaults to the full OAuth scope set', () {
    final widget = LoginScope(
      serverUrl: Uri.parse('https://meshagent.example.com'),
      callbackUrl: Uri.parse('meshagent://auth/callback'),
      oauthClientId: 'client-id',
      builder: (_) => const SizedBox.shrink(),
    );

    expect(widget.scope, fullOAuthScope);
  });
}
