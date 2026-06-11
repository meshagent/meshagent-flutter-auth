import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_auth/meshagent_flutter_auth.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Future<void> pumpOverlayFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('shared profile switcher activates a selected profile', (tester) async {
    final activeProfile = SharedProfile(
      userId: 'life-user',
      isActive: true,
      apiUrl: 'https://api.meshagent.life',
      profile: const SharedProfileInfo(id: 'life-user', firstName: 'Life', lastName: 'User'),
      session: const SharedProfileSession(accessToken: 'life-token'),
    );
    final alternateProfile = SharedProfile(
      userId: 'com-user',
      isActive: false,
      apiUrl: 'https://api.meshagent.com',
      profile: const SharedProfileInfo(id: 'com-user', email: 'com@example.com'),
      session: const SharedProfileSession(accessToken: 'com-token'),
    );
    SharedProfile? activatedProfile;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ShadButton(
              onPressed: () {
                showShadDialog<void>(
                  context: context,
                  builder: (context) => SharedProfileSwitcherDialog(
                    loadProfiles: () {
                      return Future.value(
                        SharedProfileSettingsSnapshot(
                          settingsFile: File('/tmp/unused-meshagent-settings.json'),
                          activeProfile: activeProfile,
                          profiles: [activeProfile, alternateProfile],
                          modified: DateTime.utc(2026),
                        ),
                      );
                    },
                    activateProfile: (profile) async {
                      activatedProfile = profile;
                    },
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await pumpOverlayFrames(tester);

    expect(find.text('Switch Profile'), findsOneWidget);
    expect(find.text('Life User'), findsOneWidget);
    expect(find.text('com@example.com'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);

    await tester.tap(find.text('Switch'));
    await pumpOverlayFrames(tester);

    expect(activatedProfile?.userId, 'com-user');
    expect(find.text('Switch Profile'), findsNothing);
  });

  testWidgets('shared profile switcher keeps dialog open and shows activation errors', (tester) async {
    final activeProfile = SharedProfile(
      userId: 'life-user',
      isActive: true,
      apiUrl: 'https://api.meshagent.life',
      profile: const SharedProfileInfo(id: 'life-user', firstName: 'Life', lastName: 'User'),
      session: const SharedProfileSession(accessToken: 'life-token'),
    );
    final alternateProfile = SharedProfile(
      userId: 'com-user',
      isActive: false,
      apiUrl: 'https://api.meshagent.com',
      profile: const SharedProfileInfo(id: 'com-user', email: 'com@example.com'),
      session: const SharedProfileSession(accessToken: 'com-token'),
    );
    var activationAttempts = 0;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ShadButton(
              onPressed: () {
                showShadDialog<void>(
                  context: context,
                  builder: (context) => SharedProfileSwitcherDialog(
                    loadProfiles: () {
                      return Future.value(
                        SharedProfileSettingsSnapshot(
                          settingsFile: File('/tmp/unused-meshagent-settings.json'),
                          activeProfile: activeProfile,
                          profiles: [activeProfile, alternateProfile],
                          modified: DateTime.utc(2026),
                        ),
                      );
                    },
                    activateProfile: (profile) async {
                      activationAttempts += 1;
                      throw StateError('test switch failure');
                    },
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await pumpOverlayFrames(tester);

    await tester.tap(find.text('Switch'));
    await pumpOverlayFrames(tester);

    expect(activationAttempts, 1);
    expect(find.text('Switch Profile'), findsOneWidget);
    expect(find.text('Unable to switch profile'), findsOneWidget);
    expect(find.text('Bad state: test switch failure'), findsOneWidget);
  });
}
