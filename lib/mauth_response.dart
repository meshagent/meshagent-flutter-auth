import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:localstorage/localstorage.dart';
import 'package:http/http.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'config.dart';
import 'meshagent_auth.dart';
import 'package:meshagent/meshagent.dart';

Meshagent getMeshagentClient() {
  final token = MeshagentAuth.current.getAccessToken();
  final baseUrl = MeshagentConfig.current?.serverUrl;

  if (token == null) {
    throw Exception("No access token - you are not logged in");
  }

  if (baseUrl == null) {
    throw Exception("No base URL - you are not logged in");
  }

  return Meshagent(baseUrl: baseUrl, token: token);
}

class MAuthResponsePage extends StatefulWidget {
  const MAuthResponsePage({
    super.key,
    required this.authorizationCode,
    required this.onAuthSuccess,
  });

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

  void exchangeToken() async {
    final codeVerifier = localStorage.getItem("cv");
    if (codeVerifier == null) {
      setState(() {
        error = "Missing oauthorization state, please try to login again";
      });
      return;
    }

    final res = await post(
      Uri.parse(
        MeshagentConfig.current!.serverUrl,
      ).replace(path: "/oauth/token"),
      headers: {"content-type": "application/json"},
      body: jsonEncode({
        "client_id": MeshagentConfig.current!.oauthClientId,
        "code_verifier": codeVerifier,
        "code": widget.authorizationCode,
        "grant_type": "authorization_code",
        "redirect_uri": "${MeshagentConfig.current!.appUrl}/mauth/callback",
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

    final client = getMeshagentClient();
    final me = await client.getUserProfile("me");
    MeshagentAuth.current.setUser(me);

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
