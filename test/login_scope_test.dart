import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_auth/meshagent_flutter_auth.dart';
import 'package:meshagent_flutter_auth/oauth_session_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LoginScope defaults to the full OAuth scope set', () {
    final widget = LoginScope(
      serverUrl: Uri.parse('https://meshagent.example.com'),
      callbackUrl: Uri.parse('meshagent://auth/callback'),
      oauthClientId: 'client-id',
      builder: (_) => const SizedBox.shrink(),
    );

    expect(widget.scope, fullOAuthScope);
    expect(widget.preferEphemeralAuthSession, isFalse);
  });

  test('LoginScope can prefer an ephemeral native auth session', () {
    final widget = LoginScope(
      serverUrl: Uri.parse('https://meshagent.example.com'),
      callbackUrl: Uri.parse('meshagent://auth/callback'),
      oauthClientId: 'client-id',
      preferEphemeralAuthSession: true,
      builder: (_) => const SizedBox.shrink(),
    );

    expect(widget.preferEphemeralAuthSession, isTrue);
  });

  testWidgets('LoginScope falls back to login when token refresh fails', (tester) async {
    final previousAuth = MeshagentAuth.current;
    final auth = _MemoryMeshagentAuth();
    MeshagentAuth.current = auth;
    addTearDown(() => MeshagentAuth.current = previousAuth);

    MeshagentAuth.current.setAccessToken('expired-access-token');
    MeshagentAuth.current.setRefreshToken('stale-refresh-token');
    MeshagentAuth.current.setExpiration(DateTime.now().subtract(const Duration(hours: 1)));

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScope(
          serverUrl: Uri.parse('https://meshagent.example.com'),
          callbackUrl: Uri.parse('meshagent://auth/callback'),
          oauthClientId: 'client-id',
          session: _FailingOAuthSessionManager(),
          signInBuilder: (context, isCancelled, signIn) {
            return const Text('Login required');
          },
          builder: (_) => const Text('App content'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('Login required'), findsOneWidget);
    expect(find.text('App content'), findsNothing);
    expect(find.textContaining('Failed to refresh token'), findsNothing);
    expect(MeshagentAuth.current.getAccessToken(), isNull);
    expect(MeshagentAuth.current.getRefreshToken(), isNull);
  });
}

class _MemoryMeshagentAuth extends MeshagentAuth {
  String? accessToken;
  String? refreshToken;
  DateTime? storedExpiration;
  Map<String, dynamic>? storedUser;

  @override
  void setUser(Map<String, dynamic>? user) {
    storedUser = user;
  }

  @override
  Map<String, dynamic>? getUser() {
    return storedUser;
  }

  @override
  DateTime? get expiration => storedExpiration;

  @override
  String? getAccessToken() {
    return accessToken;
  }

  @override
  String? getRefreshToken() {
    return refreshToken;
  }

  @override
  void setAccessToken(String? token) {
    accessToken = token;
  }

  @override
  void setRefreshToken(String? token) {
    refreshToken = token;
  }

  @override
  void setExpiresIn(int? expiresIn) {
    storedExpiration = expiresIn == null ? null : DateTime.now().toUtc().add(Duration(seconds: expiresIn));
  }

  @override
  void setExpiration(DateTime? expiration) {
    storedExpiration = expiration;
  }
}

class _FailingOAuthSessionManager extends OAuthSessionManager {
  _FailingOAuthSessionManager() : super(serverUrl: Uri.parse('https://meshagent.example.com'), clientId: 'client-id');

  @override
  Future<String> getValidAccessTokenOrThrow() async {
    throw Exception('Failed to refresh token: 400 {"error":"invalid_grant"}');
  }
}
