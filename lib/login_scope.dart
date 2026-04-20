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
import 'oauth_session_manager.dart';

class LoginScope extends StatefulWidget {
  const LoginScope({
    super.key,
    required this.serverUrl,
    required this.callbackUrl,
    required this.oauthClientId,
    required this.builder,
    this.scope = fullOAuthScope,
    this.onAuthenticated,
    this.signInBuilder,
    this.extraQueryParams,
  });

  final Uri serverUrl;
  final Uri callbackUrl;
  final String oauthClientId;
  final void Function(String returnUrl)? onAuthenticated;
  final Widget Function(BuildContext context) builder;
  final Widget Function(BuildContext context, bool isCancelled, void Function(String? provider) signIn)? signInBuilder;
  final Map<String, String>? extraQueryParams;
  final String scope;

  @override
  State createState() => _LoginScopeState();
}

class _LoginScopeState extends State<LoginScope> {
  Object? failed;
  bool refreshing = true;
  bool isSigningIn = false;

  bool isCancelled = false;
  bool isLoginLaunched = false;

  late final OAuthSessionManager _session = OAuthSessionManager(serverUrl: widget.serverUrl, clientId: widget.oauthClientId);

  @override
  void initState() {
    super.initState();

    load();
  }

  Future<void> _restartLoginAfterForbiddenProfileLoad() async {
    MeshagentAuth.current.signOut();

    if (widget.signInBuilder == null) {
      await signIn(null);
      return;
    }

    if (mounted) {
      setState(() {
        failed = null;
        refreshing = false;
        isLoginLaunched = true;
        isCancelled = false;
        isSigningIn = false;
      });
    }
  }

  void load() async {
    if (!MeshagentAuth.current.isLoggedIn()) {
      if (widget.signInBuilder == null) {
        await signIn(null);
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
      return;
    }

    setState(() {
      refreshing = true;
    });

    try {
      final token = await _session.getValidAccessTokenOrThrow();

      final me = await Meshagent(baseUrl: widget.serverUrl.toString(), token: token).getUserProfile("me");

      MeshagentAuth.current.setUser(me);

      if (mounted) {
        setState(() {
          failed = null;
          refreshing = false;
          isLoginLaunched = false;
          isCancelled = false;
        });
      }
    } on ForbiddenException {
      await _restartLoginAfterForbiddenProfileLoad();
    } on Exception catch (e) {
      MeshagentAuth.current.signOut();

      if (mounted) {
        setState(() {
          failed = e;
          refreshing = false;
          isLoginLaunched = true;
          isCancelled = false;
        });
      }
    }
  }

  Future<void> signIn(String? provider) async {
    try {
      setState(() {
        isSigningIn = true;
      });

      final redirectUrl = await launchOAuthLogin(provider);

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

  Future<String?> launchOAuthLogin(String? provider) async {
    final gen = PkceGenerator();

    final pair = gen.generate();

    final storage = LocalStoragePkceCache(localStorage);
    storage.saveVerifier(pair.codeVerifier);

    final eqp = widget.extraQueryParams ?? {};

    final queryParameters = <String, dynamic>{
      ...eqp,
      "scope": widget.scope,
      "client_id": widget.oauthClientId,
      "code_challenge": pair.codeChallenge,
      "response_type": "code",
      "redirect_uri": widget.callbackUrl.toString(),
      "prompt": "select_account",
    };

    if (provider != null) {
      queryParameters["provider"] = provider;
    }

    final url = widget.serverUrl.replace(path: "/oauth/authorize", queryParameters: queryParameters);

    final returnUrl = await FlutterWebAuth2.authenticate(
      url: url.toString(),
      callbackUrlScheme: widget.callbackUrl.scheme,
      options: kIsWeb ? FlutterWebAuth2Options(windowName: "_self") : FlutterWebAuth2Options(),
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
            title: Padding(padding: EdgeInsets.only(bottom: 5), child: Text("Login cancelled")),
            description: Text("Please login to continue."),
            footer: Padding(
              padding: EdgeInsets.only(top: 30),
              child: ShadButton(
                onPressed: () {
                  signIn(null);
                },
                child: Text("Login"),
              ),
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
