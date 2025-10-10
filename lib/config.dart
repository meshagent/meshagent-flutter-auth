import 'dart:convert';
import 'package:http/http.dart';

class MeshagentConfig {
  MeshagentConfig({
    required this.authUrl,
    required this.authAnonKey,
    required this.iosGoogleClientId,
    required this.webGoogleClientId,
    required this.serverUrl,
    required this.wsUrl,
    required this.appUrl,
    required this.imageTagPrefix,
    required this.authProvider,
    required this.enableBilling,
    required this.maildomains,
    required this.oauthClientId,
  });

  final String authUrl;
  final String authAnonKey;
  final String iosGoogleClientId;
  final String webGoogleClientId;
  final String serverUrl;
  final String wsUrl;
  final String appUrl;
  final String imageTagPrefix;
  final String? authProvider;
  final bool enableBilling;
  final String oauthClientId;
  final List<String> maildomains;

  static MeshagentConfig fromEnvironment() {
    return MeshagentConfig(
      authUrl: const String.fromEnvironment("AUTH_URL"),
      authAnonKey: const String.fromEnvironment("AUTH_ANON_KEY"),
      serverUrl: const String.fromEnvironment("SERVER_URL"),
      iosGoogleClientId: const String.fromEnvironment("IOS_GOOGLE_CLIENT_ID"),
      webGoogleClientId: const String.fromEnvironment("WEB_GOOGLE_CLIENT_ID"),
      wsUrl: const String.fromEnvironment("WS_URL"),
      oauthClientId: const String.fromEnvironment("OAUTH_CLIENT_ID"),
      appUrl: const String.fromEnvironment("APP_URL"),
      imageTagPrefix: const String.fromEnvironment("IMAGE_TAG_PREFIX"),
      authProvider:
          (const String.fromEnvironment("AUTH_PROVIDER")) == ""
              ? null
              : const String.fromEnvironment("AUTH_PROVIDER"),
      enableBilling: (const bool.fromEnvironment(
        "ENABLE_BILLING",
        defaultValue: true,
      )),
      maildomains: (const String.fromEnvironment("MAIL_DOMAINS")).split(","),
    );
  }

  static Future<MeshagentConfig> fromUri(Uri uri) async {
    final res = await get(uri);
    final data = jsonDecode(res.body);
    return MeshagentConfig(
      authUrl: data["AUTH_URL"],
      authAnonKey: data["AUTH_ANON_KEY"],
      serverUrl: data["SERVER_URL"],
      iosGoogleClientId: data["IOS_GOOGLE_CLIENT_ID"],
      webGoogleClientId: data["WEB_GOOGLE_CLIENT_ID"],
      wsUrl: data["WS_URL"],
      oauthClientId: data["OAUTH_CLIENT_ID"],
      appUrl: data["APP_URL"],
      imageTagPrefix: data["IMAGE_TAG_PREFIX"],
      authProvider: data["AUTH_PROVIDER"],
      enableBilling:
          data["ENABLE_BILLING"] == null || data["ENABLE_BILLING"] == true,
      maildomains: data["MAIL_DOMAINS"] ?? [],
    );
  }

  static MeshagentConfig? current;
}
