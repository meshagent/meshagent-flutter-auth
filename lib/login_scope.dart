import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:localstorage/localstorage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:http/http.dart';

import 'package:meshagent/meshagent.dart';

import 'config.dart';
import 'meshagent_auth.dart';
import 'pkce_generator.dart';

class LoginScope extends StatefulWidget {
  const LoginScope({super.key, required this.builder});

  final Widget Function(BuildContext) builder;

  @override
  State createState() => _LoginScopeState();
}

class _LoginScopeState extends State<LoginScope> {
  Exception? failed;
  bool refreshing = true;

  @override
  void initState() {
    super.initState();

    load();
  }

  void load() async {
    if (MeshagentAuth.current.isLoggedIn()) {
      try {
        if (MeshagentAuth.current.isExpired()) {
          final token = MeshagentAuth.current.getAccessToken()!;
          final me = await Meshagent(
            baseUrl: MeshagentConfig.current!.serverUrl,
            token: token,
          ).getUserProfile("me");

          MeshagentAuth.current.setUser(me);
          if (!mounted) {
            return;
          }
          setState(() {
            refreshing = false;
          });
        } else {
          // expired
          await refreshOAuthToken(
            refreshToken: MeshagentAuth.current.getRefreshToken()!,
            clientId: MeshagentConfig.current!.oauthClientId,
            tokenEndpoint: Uri.parse(
              MeshagentConfig.current!.serverUrl,
            ).replace(path: "/oauth/token"),
          );

          final token = MeshagentAuth.current.getAccessToken()!;
          final me = await Meshagent(
            baseUrl: MeshagentConfig.current!.serverUrl,
            token: token,
          ).getUserProfile("me");

          MeshagentAuth.current.setUser(me);
          if (!mounted) {
            return;
          }
          setState(() {
            refreshing = false;
          });
        }
      } on Exception catch (e) {
        MeshagentAuth.current.setAccessToken(null);
        MeshagentAuth.current.setRefreshToken(null);
        MeshagentAuth.current.setExpiresIn(null);
        if (!mounted) {
          return;
        }
        setState(() {
          failed = e;
        });
      }
    }
  }

  Future<void> refreshOAuthToken({
    required String refreshToken,
    required String clientId,
    String? clientSecret,
    required Uri tokenEndpoint,
  }) async {
    final res = await post(
      tokenEndpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
        if (clientSecret != null) 'client_secret': clientSecret,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);

      final accessToken = data["access_token"];
      final refreshToken = data["refresh_token"];

      MeshagentAuth.current.setAccessToken(accessToken);
      MeshagentAuth.current.setRefreshToken(refreshToken);

      final expiresIn = data["expires_in"];
      if (expiresIn != null) {
        MeshagentAuth.current.setExpiresIn(expiresIn);
      } else {
        MeshagentAuth.current.setExpiresIn(null);
      }
    } else {
      throw Exception('Failed to refresh token: ${res.statusCode} ${res.body}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (failed != null) {
      return Center(child: ShadAlert.destructive(title: Text("$failed")));
    }

    if (!MeshagentAuth.current.isLoggedIn() ||
        MeshagentAuth.current.isExpired()) {
      final gen = PkceGenerator();

      final pair = gen.generate();

      final storage = LocalStoragePkceCache(localStorage);
      storage.saveVerifier(pair.codeVerifier);

      launchUrl(
        Uri.parse(MeshagentConfig.current!.serverUrl).replace(
          path: "/oauth/authorize",
          queryParameters: {
            "scope": "email",
            "client_id": MeshagentConfig.current!.oauthClientId,
            "code_challenge": pair.codeChallenge,
            "response_type": "code",
            "redirect_uri": "${MeshagentConfig.current!.appUrl}/mauth/callback",
          },
        ),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: "_self",
      );
    }

    if (MeshagentAuth.current.isLoggedIn() && !refreshing) {
      return widget.builder(context);
    } else {
      return Center(child: CircularProgressIndicator());
    }
  }
}
