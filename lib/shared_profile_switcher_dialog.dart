import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'shared_profiles.dart';

typedef SharedProfileSwitcherLoader = Future<SharedProfileSettingsSnapshot> Function();
typedef SharedProfileSwitcherActivator = Future<void> Function(SharedProfile profile);

class SharedProfileSwitcherDialog extends StatefulWidget {
  const SharedProfileSwitcherDialog({super.key, required this.loadProfiles, required this.activateProfile, this.onProfileActivated});

  final SharedProfileSwitcherLoader loadProfiles;
  final SharedProfileSwitcherActivator activateProfile;
  final void Function(BuildContext context, SharedProfile profile)? onProfileActivated;

  @override
  State<SharedProfileSwitcherDialog> createState() => _SharedProfileSwitcherDialogState();
}

class _SharedProfileSwitcherDialogState extends State<SharedProfileSwitcherDialog> {
  late Future<SharedProfileSettingsSnapshot> profiles = widget.loadProfiles();
  String? switchingUserId;
  Object? error;

  Future<void> _switchProfile(SharedProfile profile) async {
    setState(() {
      switchingUserId = profile.userId;
      error = null;
    });

    try {
      await widget.activateProfile(profile);
      if (!mounted) {
        return;
      }

      widget.onProfileActivated?.call(context, profile);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        error = err;
        switchingUserId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadDialog(
      title: const Text("Switch Profile"),
      description: const Text("Choose the account or environment to use in this app."),
      constraints: const BoxConstraints(maxWidth: 680),
      actions: [ShadButton.secondary(onPressed: () => Navigator.of(context).pop(), child: const Text("Close"))],
      child: FutureBuilder(
        future: profiles,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
          }

          if (snapshot.hasError) {
            return ShadAlert.destructive(title: const Text("Unable to read profiles"), description: Text("${snapshot.error}"));
          }

          final profileList = snapshot.data?.profiles ?? const <SharedProfile>[];
          if (profileList.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text("No saved profiles were found. Sign in with a MeshAgent desktop app or another compatible MeshAgent tool first."),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) ...[
                ShadAlert.destructive(title: const Text("Unable to switch profile"), description: Text("$error")),
                const SizedBox(height: 12),
              ],
              for (final profile in profileList) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.border),
                    borderRadius: BorderRadius.circular(8),
                    color: profile.isActive ? theme.colorScheme.muted : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(profile.isActive ? LucideIcons.circleCheck : LucideIcons.userRound, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                profile.profile?.displayName ?? profile.userId,
                                style: theme.textTheme.small.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(profile.apiUrl ?? "https://api.meshagent.com", style: theme.textTheme.muted),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (profile.isActive)
                          Text("Active", style: theme.textTheme.muted)
                        else
                          ShadButton.secondary(
                            onPressed: switchingUserId == null ? () => _switchProfile(profile) : null,
                            child: switchingUserId == profile.userId
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text("Switch"),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}
