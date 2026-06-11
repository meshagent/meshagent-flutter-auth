import 'dart:convert';
import 'dart:io';

import 'meshagent_auth.dart';

const _localStateUserId = "__local__";

bool get isSharedProfilesSupported => sharedProfilesSupportedForPlatform(isMacOS: Platform.isMacOS, isWindows: Platform.isWindows);

bool sharedProfilesSupportedForPlatform({required bool isMacOS, required bool isWindows}) {
  return isMacOS || isWindows;
}

class SharedProfileSession {
  const SharedProfileSession({this.accessToken, this.refreshToken, this.expiresAt, this.tokenType = "Bearer", this.scope, this.idToken});

  factory SharedProfileSession.fromJson(Map<String, Object?> json) {
    return SharedProfileSession(
      accessToken: _nullableString(json["access_token"]),
      refreshToken: _nullableString(json["refresh_token"]),
      expiresAt: _nullableInt(json["expires_at"]),
      tokenType: _nullableString(json["token_type"]) ?? "Bearer",
      scope: _nullableString(json["scope"]),
      idToken: _nullableString(json["id_token"]),
    );
  }

  final String? accessToken;
  final String? refreshToken;
  final int? expiresAt;
  final String tokenType;
  final String? scope;
  final String? idToken;

  bool get hasAccessToken => accessToken != null && accessToken!.trim().isNotEmpty;

  DateTime? get expiresAtUtc => expiresAt == null ? null : DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000, isUtc: true);

  Map<String, Object?> toJson() {
    return {
      "access_token": accessToken,
      "refresh_token": refreshToken,
      "expires_at": expiresAt,
      "token_type": tokenType,
      "scope": scope,
      "id_token": idToken,
    };
  }
}

class SharedProfileInfo {
  const SharedProfileInfo({required this.id, this.firstName, this.lastName, this.email});

  factory SharedProfileInfo.fromJson(Map<String, Object?> json) {
    return SharedProfileInfo(
      id: _stringValue(json["id"]),
      firstName: _nullableString(json["first_name"]),
      lastName: _nullableString(json["last_name"]),
      email: _nullableString(json["email"]),
    );
  }

  final String id;
  final String? firstName;
  final String? lastName;
  final String? email;

  String get displayName {
    final fullName = [firstName, lastName].whereType<String>().map((part) => part.trim()).where((part) => part.isNotEmpty).join(" ");
    if (fullName.isNotEmpty) {
      return fullName;
    }
    final emailValue = email?.trim();
    if (emailValue != null && emailValue.isNotEmpty) {
      return emailValue;
    }
    return id;
  }

  Map<String, Object?> toJson() {
    return {"id": id, "first_name": firstName, "last_name": lastName, "email": email};
  }
}

class SharedProfile {
  const SharedProfile({required this.userId, required this.isActive, this.profile, this.apiUrl, this.session, this.activeProject});

  factory SharedProfile.fromJson({required String userId, required bool isActive, required Map<String, Object?> json}) {
    final rawProfile = json["profile"];
    final rawSession = json["session"];
    final rawProject = json["project"];
    return SharedProfile(
      userId: userId,
      isActive: isActive,
      profile: rawProfile is Map ? SharedProfileInfo.fromJson(_objectMap(rawProfile)) : null,
      apiUrl: _normalizeApiUrl(_nullableString(json["api_url"])),
      session: rawSession is Map ? SharedProfileSession.fromJson(_objectMap(rawSession)) : null,
      activeProject: rawProject is Map ? _nullableString(rawProject["active_project"]) : null,
    );
  }

  final String userId;
  final bool isActive;
  final SharedProfileInfo? profile;
  final String? apiUrl;
  final SharedProfileSession? session;
  final String? activeProject;

  bool get canAuthenticate => profile != null && session?.hasAccessToken == true;
}

class SharedProfileSettingsSnapshot {
  const SharedProfileSettingsSnapshot({required this.settingsFile, this.activeProfile, this.profiles = const [], this.modified});

  final File settingsFile;
  final SharedProfile? activeProfile;
  final List<SharedProfile> profiles;
  final DateTime? modified;
}

File sharedProfilesSettingsFile() {
  final home = Platform.environment[Platform.isWindows ? "USERPROFILE" : "HOME"]?.trim();
  if (home == null || home.isEmpty) {
    throw StateError("Unable to locate the home directory for shared profile settings.");
  }
  final separator = Platform.pathSeparator;
  return File("$home$separator.meshagent${separator}settings.json");
}

Future<SharedProfileSettingsSnapshot> loadSharedProfileSettings() {
  return loadSharedProfileSettingsFromFile(sharedProfilesSettingsFile());
}

Future<SharedProfileSettingsSnapshot> loadSharedProfileSettingsFromFile(File file) async {
  final decoded = await _readSettings(file);
  final users = decoded["users"];
  final activeUserId = _nullableString(decoded["active_user_id"]);
  final profiles = <SharedProfile>[];

  if (users is Map) {
    for (final entry in users.entries) {
      final userId = entry.key;
      final rawSettings = entry.value;
      if (userId is! String || userId == _localStateUserId || rawSettings is! Map) {
        continue;
      }

      final profile = SharedProfile.fromJson(userId: userId, isActive: userId == activeUserId, json: _objectMap(rawSettings));
      if (profile.canAuthenticate) {
        profiles.add(profile);
      }
    }
  }

  profiles.sort((a, b) {
    if (a.isActive != b.isActive) {
      return a.isActive ? -1 : 1;
    }
    return (a.profile?.displayName ?? a.userId).toLowerCase().compareTo((b.profile?.displayName ?? b.userId).toLowerCase());
  });

  return SharedProfileSettingsSnapshot(
    settingsFile: file,
    activeProfile: _firstActiveProfile(profiles),
    profiles: profiles,
    modified: await file.exists() ? await file.lastModified() : null,
  );
}

Future<SharedProfile?> loadActiveSharedProfile() async {
  return (await loadSharedProfileSettings()).activeProfile;
}

Future<SharedProfile?> hydrateCurrentAuthFromActiveSharedProfile() async {
  final activeProfile = await loadActiveSharedProfile();
  if (activeProfile == null || !activeProfile.canAuthenticate) {
    return null;
  }

  final session = activeProfile.session!;
  MeshagentAuth.current.setAccessToken(session.accessToken);
  MeshagentAuth.current.setRefreshToken(session.refreshToken);
  MeshagentAuth.current.setExpiration(session.expiresAtUtc);
  MeshagentAuth.current.setUser(activeProfile.profile!.toJson());
  return activeProfile;
}

Future<SharedProfile> setActiveSharedProfileInFile({required File file, required String userId}) async {
  final settings = await _readSettings(file);
  final users = settings["users"];
  if (users is! Map || users[userId] is! Map) {
    throw StateError("No saved profile matches $userId.");
  }

  settings["active_user_id"] = userId;
  await _writeSettings(file, settings);
  final snapshot = await loadSharedProfileSettingsFromFile(file);
  final selected = snapshot.activeProfile;
  if (selected == null || selected.userId != userId) {
    throw StateError("Unable to activate profile $userId.");
  }
  return selected;
}

Future<void> writeSharedProfileToFile({
  required File file,
  required String userId,
  required SharedProfileInfo profile,
  required SharedProfileSession session,
  String? apiUrl,
  String? activeProject,
}) async {
  if (!session.hasAccessToken || userId.trim().isEmpty) {
    return;
  }

  final settings = await _readSettings(file);
  final users = _ensureMap(settings, "users");
  final userSettings = _ensureMap(users, userId);

  _mergeLocalProjectIntoProfile(users: users, userSettings: userSettings, userId: userId);

  userSettings["profile"] = profile.toJson();
  userSettings["api_url"] = _normalizeApiUrl(apiUrl);
  userSettings["session"] = session.toJson();
  if (activeProject != null && activeProject.trim().isNotEmpty) {
    final projectSettings = _ensureMap(userSettings, "project");
    projectSettings["active_project"] = activeProject.trim();
  }

  users.remove(_localStateUserId);
  settings["active_user_id"] = userId;
  await _writeSettings(file, settings);
}

Future<void> syncCurrentAuthToSharedProfileFile({required File file, String? apiUrl, String? activeProject}) async {
  final token = MeshagentAuth.current.getAccessToken();
  final user = MeshagentAuth.current.getUser();
  final userId = _stringValue(user?["id"]);
  if (token == null || token.trim().isEmpty || userId.isEmpty) {
    return;
  }

  final expiration = MeshagentAuth.current.expiration;
  await writeSharedProfileToFile(
    file: file,
    userId: userId,
    profile: SharedProfileInfo(
      id: userId,
      firstName: _nullableString(user?["first_name"]),
      lastName: _nullableString(user?["last_name"]),
      email: _nullableString(user?["email"]),
    ),
    apiUrl: apiUrl,
    session: SharedProfileSession(
      accessToken: token,
      refreshToken: MeshagentAuth.current.getRefreshToken(),
      expiresAt: expiration == null ? null : expiration.toUtc().millisecondsSinceEpoch ~/ 1000,
      tokenType: "Bearer",
    ),
    activeProject: activeProject,
  );
}

Future<Map<String, Object?>> _readSettings(File file) async {
  if (!await file.exists()) {
    return <String, Object?>{"active_user_id": null, "users": <String, Object?>{}};
  }

  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    return <String, Object?>{"active_user_id": null, "users": <String, Object?>{}};
  }
  return _objectMap(decoded);
}

Future<void> _writeSettings(File file, Map<String, Object?> settings) async {
  await file.parent.create(recursive: true);
  await file.writeAsString("${const JsonEncoder.withIndent("  ").convert(settings)}\n");
}

Map<String, Object?> _ensureMap(Map<dynamic, dynamic> parent, String key) {
  final current = parent[key];
  if (current is Map) {
    final normalized = _objectMap(current);
    parent[key] = normalized;
    return normalized;
  }
  final next = <String, Object?>{};
  parent[key] = next;
  return next;
}

void _mergeLocalProjectIntoProfile({
  required Map<String, Object?> users,
  required Map<String, Object?> userSettings,
  required String userId,
}) {
  if (userId == _localStateUserId) {
    return;
  }

  final localSettings = users[_localStateUserId];
  if (localSettings is! Map) {
    return;
  }

  final localProject = localSettings["project"];
  if (localProject is! Map) {
    return;
  }

  final projectSettings = _ensureMap(userSettings, "project");
  final existingApiKeys = projectSettings["active_api_keys"];
  final localProjectMap = _objectMap(localProject);
  final localApiKeys = localProjectMap["active_api_keys"];

  projectSettings.addAll(localProjectMap);

  if (existingApiKeys is Map || localApiKeys is Map) {
    projectSettings["active_api_keys"] = {
      if (existingApiKeys is Map) ..._objectMap(existingApiKeys),
      if (localApiKeys is Map) ..._objectMap(localApiKeys),
    };
  }
}

SharedProfile? _firstActiveProfile(List<SharedProfile> profiles) {
  for (final profile in profiles) {
    if (profile.isActive) {
      return profile;
    }
  }
  return null;
}

Map<String, Object?> _objectMap(Map<dynamic, dynamic> map) {
  return map.map((key, value) => MapEntry(key.toString(), value));
}

String _stringValue(Object? value) {
  final normalized = _nullableString(value);
  return normalized ?? "";
}

String? _nullableString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _nullableInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

String? _normalizeApiUrl(String? apiUrl) {
  if (apiUrl == null) {
    return null;
  }
  return apiUrl.endsWith("/") ? apiUrl.substring(0, apiUrl.length - 1) : apiUrl;
}
