bool get isSharedProfilesSupported => false;

class SharedProfileSession {
  const SharedProfileSession({this.accessToken, this.refreshToken, this.expiresAt, this.tokenType = "Bearer", this.scope, this.idToken});

  final String? accessToken;
  final String? refreshToken;
  final int? expiresAt;
  final String tokenType;
  final String? scope;
  final String? idToken;

  bool get hasAccessToken => accessToken != null && accessToken!.trim().isNotEmpty;

  DateTime? get expiresAtUtc => expiresAt == null ? null : DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000, isUtc: true);
}

class SharedProfileInfo {
  const SharedProfileInfo({required this.id, this.firstName, this.lastName, this.email});

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
}

class SharedProfile {
  const SharedProfile({required this.userId, required this.isActive, this.profile, this.apiUrl, this.session, this.activeProject});

  final String userId;
  final bool isActive;
  final SharedProfileInfo? profile;
  final String? apiUrl;
  final SharedProfileSession? session;
  final String? activeProject;
}

class SharedProfileSettingsSnapshot {
  const SharedProfileSettingsSnapshot({this.settingsFile, this.activeProfile, this.profiles = const [], this.modified});

  final Object? settingsFile;
  final SharedProfile? activeProfile;
  final List<SharedProfile> profiles;
  final DateTime? modified;
}

Object sharedProfilesSettingsFile() {
  throw UnsupportedError("Shared profiles are only available in native desktop apps.");
}

Future<SharedProfileSettingsSnapshot> loadSharedProfileSettings() async {
  return const SharedProfileSettingsSnapshot();
}

Future<SharedProfileSettingsSnapshot> loadSharedProfileSettingsFromFile(Object file) async {
  return const SharedProfileSettingsSnapshot();
}

Future<SharedProfile?> loadActiveSharedProfile() async {
  return null;
}

Future<SharedProfile?> hydrateCurrentAuthFromActiveSharedProfile() async {
  return null;
}

Future<SharedProfile> setActiveSharedProfileInFile({required Object file, required String userId}) async {
  throw UnsupportedError("Shared profiles are only available in native desktop apps.");
}

Future<void> writeSharedProfileToFile({
  required Object file,
  required String userId,
  required SharedProfileInfo profile,
  required SharedProfileSession session,
  String? apiUrl,
  String? activeProject,
}) async {}

Future<void> syncCurrentAuthToSharedProfileFile({required Object file, String? apiUrl, String? activeProject}) async {}
