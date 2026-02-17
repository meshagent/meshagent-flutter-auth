import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'meshagent_auth.dart';

class OAuthSessionManager {
  OAuthSessionManager({
    required this.serverUrl,
    required this.clientId,
    this.clientSecret,
    this.refreshSkew = const Duration(minutes: 2),
    this.minValidFor = const Duration(hours: 8),
  });

  final Uri serverUrl;
  final String clientId;
  final String? clientSecret;

  /// Refresh a little early to avoid edge-of-expiry failures.
  final Duration refreshSkew;

  /// Your current heuristic: treat tokens as “good” if valid at least 8 hours more.
  /// If you want “refresh only when nearly expired”, set this to Duration.zero.
  final Duration minValidFor;

  Uri get _tokenEndpoint => serverUrl.replace(path: "/oauth/token");

  bool get isLoggedIn => MeshagentAuth.current.isLoggedIn();

  /// Returns current access token if sufficiently valid, otherwise refreshes.
  /// Throws if not logged in or refresh fails.
  Future<String> getValidAccessTokenOrThrow() async {
    final token = MeshagentAuth.current.getAccessToken();

    if (token == null || token.isEmpty) {
      throw StateError('Not logged in');
    }

    if (_isAccessTokenValidEnough()) {
      return token;
    }

    await refreshOrThrow();

    final newToken = MeshagentAuth.current.getAccessToken();
    if (newToken == null || newToken.isEmpty) {
      throw StateError('Refresh succeeded but access token missing');
    }

    return newToken;
  }

  bool _isAccessTokenValidEnough() {
    final exp = MeshagentAuth.current.expiration;
    if (exp == null) return false;

    final now = DateTime.now();
    final threshold = now.add(minValidFor).add(refreshSkew);
    return exp.isAfter(threshold);
  }

  Future<void> refreshOrThrow() async {
    final refreshToken = MeshagentAuth.current.getRefreshToken();

    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('No refresh token available');
    }

    final response = await http.post(
      _tokenEndpoint,
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
        if (clientSecret != null) 'client_secret': clientSecret,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to refresh token: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    final accessToken = data["access_token"];
    final newRefreshToken = data["refresh_token"]; // may be absent
    final expiresIn = data["expires_in"];

    if (accessToken is! String || accessToken.isEmpty) {
      throw Exception('Refresh response missing access_token');
    }

    MeshagentAuth.current.setAccessToken(accessToken);

    // Keep old refresh token if server doesn’t rotate.
    if (newRefreshToken is String && newRefreshToken.isNotEmpty) {
      MeshagentAuth.current.setRefreshToken(newRefreshToken);
    }

    MeshagentAuth.current.setExpiresIn(expiresIn);
  }
}
