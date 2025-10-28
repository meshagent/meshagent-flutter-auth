import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localstorage/localstorage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:http/http.dart';

import 'package:meshagent/meshagent.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'config.dart';
import 'meshagent_auth.dart';
import 'pkce_generator.dart';

class LoginScope extends StatefulWidget {
  const LoginScope({super.key, this.callbackUrlScheme, required this.builder});

  final String? callbackUrlScheme;
  final Widget Function(BuildContext) builder;

  @override
  State createState() => _LoginScopeState();
}

class _LoginScopeState extends State<LoginScope> {
  Object? failed;
  bool refreshing = true;

  @override
  void initState() {
    super.initState();

    load();
  }

  void load() async {
    if (MeshagentAuth.current.isLoggedIn()) {
      try {
        if (MeshagentAuth.current.expiration?.isBefore(
              DateTime.now().add(Duration(days: 1)),
            ) ??
            false) {
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
    } else {
      try {
        await launchOAuthLogin();

        if (mounted) {
          setState(() {
            refreshing = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            failed = e;
          });
        }
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

  Future<String?> launchOAuthLogin() async {
    final gen = PkceGenerator();

    final pair = gen.generate();

    final storage = LocalStoragePkceCache(localStorage);
    storage.saveVerifier(pair.codeVerifier);

    final url = Uri.parse(MeshagentConfig.current!.serverUrl).replace(
      path: "/oauth/authorize",
      queryParameters: {
        "scope": "email",
        "client_id": MeshagentConfig.current!.oauthClientId,
        "code_challenge": pair.codeChallenge,
        "response_type": "code",
        "redirect_uri": "${MeshagentConfig.current!.appUrl}/mauth/callback",
      },
    );

    if (kIsWeb) {
      final returnUrl = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: url.scheme,
        options: FlutterWebAuth2Options(windowName: "_self"),
      );
      return returnUrl;
    } else {
      final returnUrl = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: url.scheme,
        options: FlutterWebAuth2Options(),
      );
      return returnUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (failed != null) {
      return Center(child: ShadAlert.destructive(title: Text("$failed")));
    }

    if (MeshagentAuth.current.isLoggedIn() && !refreshing) {
      return widget.builder(context);
    } else {
      return Center(child: CircularProgressIndicator());
    }
  }
}
