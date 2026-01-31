import 'package:meshagent/meshagent.dart';
import 'oauth_session_manager.dart';

class RefreshAccessTokenProvider implements AccessTokenProvider {
  RefreshAccessTokenProvider({required String oauthClientId, required Uri serverUrl})
    : _session = OAuthSessionManager(clientId: oauthClientId, serverUrl: serverUrl);

  final OAuthSessionManager _session;

  @override
  Future<String> getToken() => _session.getValidAccessTokenOrThrow();
}
