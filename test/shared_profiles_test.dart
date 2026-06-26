import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_auth/shared_profiles.dart';

void main() {
  test('shared profile settings loader reads active profile and filters unusable records', () async {
    final temp = await Directory.systemTemp.createTemp('shared-profile-read-test-');
    addTearDown(() => temp.delete(recursive: true));
    final settingsFile = File('${temp.path}/settings.json');
    await settingsFile.writeAsString(
      jsonEncode({
        'active_user_id': 'life-user',
        'users': {
          '__local__': {
            'api_url': 'https://local.meshagent.test',
            'session': {'access_token': 'local-token'},
          },
          'life-user': {
            'api_url': 'https://api.meshagent.life/',
            'profile': {'id': 'life-user', 'first_name': 'Life', 'last_name': 'User', 'email': 'life@example.com'},
            'session': {'access_token': 'life-token', 'refresh_token': 'life-refresh', 'expires_at': 1800000000},
            'project': {'active_project': 'project-life'},
          },
          'com-user': {
            'api_url': 'https://api.meshagent.com',
            'profile': {'id': 'com-user', 'email': 'com@example.com'},
            'session': {'access_token': 'com-token'},
          },
          'missing-token': {
            'api_url': 'https://api.meshagent.com',
            'profile': {'id': 'missing-token', 'email': 'missing@example.com'},
            'session': {},
          },
        },
      }),
    );

    final snapshot = await loadSharedProfileSettingsFromFile(settingsFile);

    expect(snapshot.profiles.map((profile) => profile.userId), ['life-user', 'com-user']);
    expect(snapshot.activeProfile?.userId, 'life-user');
    expect(snapshot.activeProfile?.apiUrl, 'https://api.meshagent.life');
    expect(snapshot.activeProfile?.profile?.displayName, 'Life User');
    expect(snapshot.activeProfile?.activeProject, 'project-life');
  });

  test('shared profile switch updates active_user_id in settings file', () async {
    final temp = await Directory.systemTemp.createTemp('shared-profile-switch-test-');
    addTearDown(() => temp.delete(recursive: true));
    final settingsFile = File('${temp.path}/settings.json');
    await settingsFile.writeAsString(
      jsonEncode({
        'active_user_id': 'life-user',
        'users': {
          'life-user': {
            'api_url': 'https://api.meshagent.life',
            'profile': {'id': 'life-user', 'email': 'life@example.com'},
            'session': {'access_token': 'life-token'},
          },
          'com-user': {
            'api_url': 'https://api.meshagent.com',
            'profile': {'id': 'com-user', 'email': 'com@example.com'},
            'session': {'access_token': 'com-token'},
          },
        },
      }),
    );

    final selected = await setActiveSharedProfileInFile(file: settingsFile, userId: 'com-user');
    final decoded = jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;

    expect(selected.userId, 'com-user');
    expect(decoded['active_user_id'], 'com-user');
  });

  test('shared profile writer preserves other profiles and removes local state', () async {
    final temp = await Directory.systemTemp.createTemp('shared-profile-write-test-');
    addTearDown(() => temp.delete(recursive: true));
    final settingsFile = File('${temp.path}/settings.json');
    await settingsFile.writeAsString(
      jsonEncode({
        'active_user_id': 'other-user',
        'users': {
          '__local__': {'api_url': 'https://api.meshagent.com'},
          'other-user': {
            'api_url': 'https://api.meshagent.com',
            'profile': {'id': 'other-user', 'email': 'other@example.com'},
            'session': {'access_token': 'other-token'},
          },
        },
      }),
    );

    await writeSharedProfileToFile(
      file: settingsFile,
      userId: 'studio-user',
      profile: const SharedProfileInfo(id: 'studio-user', firstName: 'Studio', lastName: 'User', email: 'studio@example.com'),
      apiUrl: 'https://api.meshagent.life/',
      session: const SharedProfileSession(accessToken: 'studio-token', refreshToken: 'studio-refresh', expiresAt: 1800000000),
      activeProject: 'project-123',
    );

    final decoded = jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
    final users = decoded['users'] as Map<String, dynamic>;
    final studioSettings = users['studio-user'] as Map<String, dynamic>;
    final studioProject = studioSettings['project'] as Map<String, dynamic>;
    final studioSession = studioSettings['session'] as Map<String, dynamic>;

    expect(decoded['active_user_id'], 'studio-user');
    expect(users.containsKey('__local__'), isFalse);
    expect(users.containsKey('other-user'), isTrue);
    expect(studioSettings['api_url'], 'https://api.meshagent.life');
    expect(studioProject['active_project'], 'project-123');
    expect(studioSession['access_token'], 'studio-token');
    expect(studioSession['refresh_token'], 'studio-refresh');
    expect(studioSession['expires_at'], 1800000000);
  });

  test('shared profile writer migrates local project settings into authenticated profile', () async {
    final temp = await Directory.systemTemp.createTemp('shared-profile-local-project-test-');
    addTearDown(() => temp.delete(recursive: true));
    final settingsFile = File('${temp.path}/settings.json');
    await settingsFile.writeAsString(
      jsonEncode({
        'active_user_id': '__local__',
        'users': {
          '__local__': {
            'api_url': 'https://api.meshagent.life',
            'project': {
              'active_project': 'local-project',
              'active_api_keys': {'local-project': 'local-key'},
              'llm_proxy_bearer_token': 'local-llm-token',
            },
          },
          'studio-user': {
            'api_url': 'https://api.meshagent.life',
            'profile': {'id': 'studio-user', 'email': 'studio@example.com'},
            'session': {'access_token': 'old-token'},
            'project': {
              'active_api_keys': {'existing-project': 'existing-key'},
            },
          },
        },
      }),
    );

    await writeSharedProfileToFile(
      file: settingsFile,
      userId: 'studio-user',
      profile: const SharedProfileInfo(id: 'studio-user', email: 'studio@example.com'),
      apiUrl: 'https://api.meshagent.life',
      session: const SharedProfileSession(accessToken: 'studio-token'),
    );

    final decoded = jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
    final users = decoded['users'] as Map<String, dynamic>;
    final studioSettings = users['studio-user'] as Map<String, dynamic>;
    final studioProject = studioSettings['project'] as Map<String, dynamic>;
    final activeApiKeys = studioProject['active_api_keys'] as Map<String, dynamic>;

    expect(decoded['active_user_id'], 'studio-user');
    expect(users.containsKey('__local__'), isFalse);
    expect(studioProject['active_project'], 'local-project');
    expect(studioProject['llm_proxy_bearer_token'], 'local-llm-token');
    expect(activeApiKeys['existing-project'], 'existing-key');
    expect(activeApiKeys['local-project'], 'local-key');
  });

  test('shared profile writer creates settings file on first login', () async {
    final temp = await Directory.systemTemp.createTemp('shared-profile-first-login-test-');
    addTearDown(() => temp.delete(recursive: true));
    final settingsFile = File('${temp.path}/nested/.meshagent/settings.json');

    expect(await settingsFile.exists(), isFalse);
    final emptySnapshot = await loadSharedProfileSettingsFromFile(settingsFile);
    expect(emptySnapshot.profiles, isEmpty);
    expect(emptySnapshot.activeProfile, isNull);

    await writeSharedProfileToFile(
      file: settingsFile,
      userId: 'fresh-user',
      profile: const SharedProfileInfo(id: 'fresh-user', firstName: 'Fresh', lastName: 'User', email: 'fresh@example.com'),
      apiUrl: 'https://api.meshagent.life',
      session: const SharedProfileSession(accessToken: 'fresh-token', refreshToken: 'fresh-refresh', expiresAt: 1800000000),
    );

    expect(await settingsFile.exists(), isTrue);
    final decoded = jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
    final users = decoded['users'] as Map<String, dynamic>;
    final userSettings = users['fresh-user'] as Map<String, dynamic>;
    final profile = userSettings['profile'] as Map<String, dynamic>;
    final session = userSettings['session'] as Map<String, dynamic>;

    expect(decoded['active_user_id'], 'fresh-user');
    expect(userSettings['api_url'], 'https://api.meshagent.life');
    expect(profile['email'], 'fresh@example.com');
    expect(session['access_token'], 'fresh-token');
    expect(session['refresh_token'], 'fresh-refresh');
  });

  test('shared profile operations do not print tokens', () async {
    final temp = await Directory.systemTemp.createTemp('shared-profile-token-log-test-');
    addTearDown(() => temp.delete(recursive: true));
    final settingsFile = File('${temp.path}/settings.json');
    await settingsFile.writeAsString(
      jsonEncode({
        'active_user_id': 'life-user',
        'users': {
          'life-user': {
            'api_url': 'https://api.meshagent.life',
            'profile': {'id': 'life-user', 'email': 'life@example.com'},
            'session': {'access_token': 'secret-access-token', 'refresh_token': 'secret-refresh-token', 'id_token': 'secret-id-token'},
          },
          'com-user': {
            'api_url': 'https://api.meshagent.com',
            'profile': {'id': 'com-user', 'email': 'com@example.com'},
            'session': {'access_token': 'secret-com-token'},
          },
        },
      }),
    );
    final printed = <String>[];

    await runZoned(() async {
      await loadSharedProfileSettingsFromFile(settingsFile);
      await setActiveSharedProfileInFile(file: settingsFile, userId: 'com-user');
      await writeSharedProfileToFile(
        file: settingsFile,
        userId: 'studio-user',
        profile: const SharedProfileInfo(id: 'studio-user', email: 'studio@example.com'),
        session: const SharedProfileSession(
          accessToken: 'secret-studio-access-token',
          refreshToken: 'secret-studio-refresh-token',
          idToken: 'secret-studio-id-token',
        ),
      );
    }, zoneSpecification: ZoneSpecification(print: (_, _, _, message) => printed.add(message)));

    final logText = printed.join('\n');
    expect(printed, isEmpty);
    expect(logText, isNot(contains('secret-access-token')));
    expect(logText, isNot(contains('secret-refresh-token')));
    expect(logText, isNot(contains('secret-id-token')));
    expect(logText, isNot(contains('secret-studio-access-token')));
  });
}
