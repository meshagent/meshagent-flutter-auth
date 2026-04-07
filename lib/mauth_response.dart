import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:localstorage/localstorage.dart';
import 'package:http/http.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'meshagent_auth.dart';
import 'package:meshagent/meshagent.dart';

class MAuthResponsePage extends StatefulWidget {
  const MAuthResponsePage({
    super.key,
    required this.serverUrl,
    required this.callbackUrl,
    required this.oauthClientId,
    required this.authorizationCode,
    required this.onAuthSuccess,
  });

  final Uri serverUrl;
  final Uri callbackUrl;
  final String oauthClientId;
  final String authorizationCode;
  final VoidCallback onAuthSuccess;

  @override
  State createState() => _MAuthResponsePage();
}

class _MAuthResponsePage extends State<MAuthResponsePage> {
  String? error;

  @override
  void initState() {
    super.initState();

    exchangeToken();
  }

  Meshagent getMeshagentClient() {
    final token = MeshagentAuth.current.getAccessToken();
    final baseUrl = widget.serverUrl.toString();

    if (token == null) {
      throw Exception("No access token - you are not logged in");
    }

    return Meshagent(baseUrl: baseUrl, token: token);
  }

  void exchangeToken() async {
    final codeVerifier = localStorage.getItem("cv");
    if (codeVerifier == null) {
      setState(() {
        error = "Missing oauthorization state, please try to login again";
      });
      return;
    }

    final res = await post(
      widget.serverUrl.replace(path: "/oauth/token"),
      headers: {"content-type": "application/json"},
      body: jsonEncode({
        "client_id": widget.oauthClientId,
        "code_verifier": codeVerifier,
        "code": widget.authorizationCode,
        "grant_type": "authorization_code",
        "redirect_uri": widget.callbackUrl.toString(),
      }),
    );

    if (res.statusCode != 200) {
      setState(() {
        error = "Unable to login";
      });
      return;
    }

    final data = jsonDecode(res.body);
    final accessToken = data["access_token"];
    final refreshToken = data["refresh_token"];

    MeshagentAuth.current.setAccessToken(accessToken);
    MeshagentAuth.current.setRefreshToken(refreshToken);

    try {
      final client = getMeshagentClient();
      final me = await client.getUserProfile("me");
      MeshagentAuth.current.setUser(me);
    } on ForbiddenException {
      MeshagentAuth.current.signOut();
      widget.onAuthSuccess();
      return;
    } on Exception catch (e) {
      MeshagentAuth.current.signOut();
      if (mounted) {
        setState(() {
          error = e.toString();
        });
      }
      return;
    }

    final expiresIn = data["expires_in"];
    if (expiresIn != null) {
      MeshagentAuth.current.setExpiresIn(expiresIn);
    } else {
      MeshagentAuth.current.setExpiresIn(null);
    }

    widget.onAuthSuccess();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(child: ShadAlert(title: Text(error!)));
    }

    return Center(child: CircularProgressIndicator());
  }
}
