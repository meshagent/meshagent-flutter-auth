import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localstorage/localstorage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:http/http.dart';

import 'package:meshagent/meshagent.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'meshagent_auth.dart';
import 'pkce_generator.dart';

class LoginScope extends StatefulWidget {
  const LoginScope({
    super.key,
    required this.serverUrl,
    required this.callbackUrl,
    required this.oauthClientId,
    this.onAuthenticated,
    required this.builder,
    this.signInBuilder,
  });

  final Uri serverUrl;
  final Uri callbackUrl;
  final String oauthClientId;
  final void Function(String returnUrl)? onAuthenticated;
  final Widget Function(BuildContext context) builder;
  final Widget Function(
    BuildContext context,
    bool isCancelled,
    VoidCallback signIn,
  )?
  signInBuilder;

  @override
  State createState() => _LoginScopeState();
}

class _LoginScopeState extends State<LoginScope> {
  Object? failed;
  bool refreshing = true;
  bool isSigningIn = false;

  bool isCancelled = false;
  bool isLoginLaunched = false;

  @override
  void initState() {
    super.initState();

    load();
  }

  void load() async {
    if (MeshagentAuth.current.isLoggedIn()) {
      try {
        if (MeshagentAuth.current.expiration?.isAfter(
              DateTime.now().add(Duration(hours: 8)),
            ) ??
            false) {
          final token = MeshagentAuth.current.getAccessToken()!;
          final me = await Meshagent(
            baseUrl: widget.serverUrl.toString(),
            token: token,
          ).getUserProfile("me");

          MeshagentAuth.current.setUser(me);
          if (mounted) {
            setState(() {
              failed = null;
              refreshing = false;
              isLoginLaunched = false;
              isCancelled = false;
            });
          }
        } else {
          setState(() {
            refreshing = true;
          });

          // expired
          await refreshOAuthToken(
            refreshToken: MeshagentAuth.current.getRefreshToken()!,
            clientId: widget.oauthClientId,
            tokenEndpoint: widget.serverUrl.replace(path: "/oauth/token"),
          );

          final token = MeshagentAuth.current.getAccessToken()!;

          final me = await Meshagent(
            baseUrl: widget.serverUrl.toString(),
            token: token,
          ).getUserProfile("me");

          MeshagentAuth.current.setUser(me);

          if (mounted) {
            setState(() {
              failed = null;
              refreshing = false;
              isLoginLaunched = false;
              isCancelled = false;
            });
          }
        }
      } on Exception catch (e) {
        MeshagentAuth.current.setAccessToken(null);
        MeshagentAuth.current.setRefreshToken(null);
        MeshagentAuth.current.setExpiresIn(null);

        if (mounted) {
          setState(() {
            failed = e;
            refreshing = false;
            isLoginLaunched = true;
            isCancelled = false;
          });
        }
      }
    } else {
      if (widget.signInBuilder == null) {
        await signIn();
      } else {
        if (mounted) {
          setState(() {
            failed = null;
            refreshing = false;
            isLoginLaunched = true;
            isCancelled = false;
          });
        }
      }
    }
  }

  Future<void> signIn() async {
    try {
      setState(() {
        isSigningIn = true;
      });

      final redirectUrl = await launchOAuthLogin();

      if (redirectUrl != null) {
        widget.onAuthenticated?.call(redirectUrl);
      }

      if (mounted) {
        setState(() {
          failed = null;
          refreshing = false;
          isLoginLaunched = false;
          isCancelled = false;
          isSigningIn = false;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          failed = e;
          refreshing = false;
          isLoginLaunched = true;
          isCancelled = e.code.toLowerCase().contains('cancel');
          isSigningIn = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          failed = e;
          refreshing = false;
          isLoginLaunched = false;
          isCancelled = false;
          isSigningIn = false;
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

  Future<String?> launchOAuthLogin() async {
    final gen = PkceGenerator();

    final pair = gen.generate();

    final storage = LocalStoragePkceCache(localStorage);
    storage.saveVerifier(pair.codeVerifier);

    final url = widget.serverUrl.replace(
      path: "/oauth/authorize",
      queryParameters: {
        "scope": "email",
        "client_id": widget.oauthClientId,
        "code_challenge": pair.codeChallenge,
        "response_type": "code",
        "redirect_uri": widget.callbackUrl.toString(),
      },
    );

    final returnUrl = await FlutterWebAuth2.authenticate(
      url: url.toString(),
      callbackUrlScheme: widget.callbackUrl.scheme,
      options:
          kIsWeb
              ? FlutterWebAuth2Options(windowName: "_self")
              : FlutterWebAuth2Options(),
    );

    return returnUrl;
  }

  @override
  Widget build(BuildContext context) {
    if (isSigningIn || refreshing) {
      return Center(child: CircularProgressIndicator());
    }

    if (isLoginLaunched && widget.signInBuilder != null) {
      return widget.signInBuilder!.call(context, isCancelled, signIn);
    }

    if (isCancelled) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: ShadCard(
            rowMainAxisSize: MainAxisSize.max,
            rowMainAxisAlignment: MainAxisAlignment.center,
            columnCrossAxisAlignment: CrossAxisAlignment.center,
            title: Padding(
              padding: EdgeInsets.only(bottom: 5),
              child: Text("Login cancelled"),
            ),
            description: Text("Please login to continue."),
            footer: Padding(
              padding: EdgeInsets.only(top: 30),
              child: ShadButton(onPressed: signIn, child: Text("Login")),
            ),
          ),
        ),
      );
    }

    if (failed != null) {
      return Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: ShadAlert.destructive(title: Text("$failed"))),
      );
    }

    if (MeshagentAuth.current.isLoggedIn()) {
      return widget.builder(context);
    }

    return Center(child: CircularProgressIndicator());
  }
}
