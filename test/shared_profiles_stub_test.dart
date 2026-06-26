import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_auth/shared_profiles_stub.dart' as stub;

void main() {
  test('shared profile stub is unsupported and returns empty state', () async {
    expect(stub.isSharedProfilesSupported, isFalse);
    expect(stub.sharedProfilesSettingsFile, throwsUnsupportedError);

    final snapshot = await stub.loadSharedProfileSettings();
    expect(snapshot.settingsFile, isNull);
    expect(snapshot.activeProfile, isNull);
    expect(snapshot.profiles, isEmpty);
    expect(snapshot.modified, isNull);

    expect(await stub.loadSharedProfileSettingsFromFile(Object()), isA<stub.SharedProfileSettingsSnapshot>());
    expect(await stub.loadActiveSharedProfile(), isNull);
  });

  test('shared profile stub does not write or switch profiles', () async {
    expect(() => stub.setActiveSharedProfileInFile(file: Object(), userId: 'user-1'), throwsUnsupportedError);

    await stub.writeSharedProfileToFile(
      file: Object(),
      userId: 'user-1',
      profile: const stub.SharedProfileInfo(id: 'user-1'),
      session: const stub.SharedProfileSession(accessToken: 'token'),
      apiUrl: 'https://api.meshagent.test',
    );
    await stub.syncCurrentAuthToSharedProfileFile(file: Object(), apiUrl: 'https://api.meshagent.test');
  });
}
