import 'package:localstorage/localstorage.dart';

class MeshagentAuth {
  static MeshagentAuth current = MeshagentAuth();

  Map<String, dynamic>? _user;

  void setUser(Map<String, dynamic>? user) {
    _user = user;
  }

  Map<String, dynamic>? getUser() {
    return _user;
  }

  void signOut() {
    setAccessToken(null);
    setRefreshToken(null);
    setExpiresIn(null);
    setUser(null);
  }

  bool isLoggedIn() {
    return getAccessToken() != null;
  }

  DateTime? get expiration {
    final exp = localStorage.getItem("ma:expiration");
    if (exp != null) {
      return DateTime.parse(exp);
    }
    return null;
  }

  bool isExpired() {
    return expiration?.isBefore(DateTime.now()) ?? false;
  }

  String? getAccessToken() {
    return localStorage.getItem("ma:access_token");
  }

  String? getRefreshToken() {
    return localStorage.getItem("ma:refresh_token");
  }

  void setAccessToken(String? token) {
    if (token == null) {
      localStorage.removeItem("ma:access_token");
    } else {
      localStorage.setItem("ma:access_token", token);
    }
  }

  void setRefreshToken(String? refreshToken) {
    if (refreshToken == null) {
      localStorage.removeItem("ma:refresh_token");
    } else {
      localStorage.setItem("ma:refresh_token", refreshToken);
    }
  }

  void setExpiresIn(int? expiresIn) {
    if (expiresIn == null) {
      localStorage.removeItem("ma:expiration");
    } else {
      localStorage.setItem("ma:expiration", DateTime.now().toUtc().add(Duration(seconds: expiresIn)).toIso8601String());
    }
  }
}
