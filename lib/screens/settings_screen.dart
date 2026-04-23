import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SectionCard(
            title: 'Project',
            subtitle: 'Save, load, and organize project files.',
            children: [
              _ActionRow(
                icon: Icons.save_rounded,
                title: 'Save Project',
                subtitle: 'Store current session state on device',
                onTap: () => _showComingSoon(context, 'Save Project'),
              ),
              _ActionRow(
                icon: Icons.folder_open_rounded,
                title: 'Load Project',
                subtitle: 'Open a previously saved project',
                onTap: () => _showComingSoon(context, 'Load Project'),
              ),
              _ActionRow(
                icon: Icons.drive_file_rename_outline_rounded,
                title: 'Rename Current Project',
                subtitle: 'Name your session for faster recall',
                onTap: () => _showComingSoon(context, 'Rename Current Project'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SectionCard(
            title: 'Export',
            subtitle: 'Render your work for sharing and production.',
            children: [
              _ActionRow(
                icon: Icons.music_note_rounded,
                title: 'Export Mixdown',
                subtitle: 'Single bounced file of the full session',
                onTap: () => _showComingSoon(context, 'Export Mixdown'),
              ),
              _ActionRow(
                icon: Icons.library_music_rounded,
                title: 'Export Stems',
                subtitle: 'One file per track for DAW workflows',
                onTap: () => _showComingSoon(context, 'Export Stems'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SectionCard(
            title: 'Pro',
            subtitle: 'Unlock future premium features from one place.',
            children: [
              _ActionRow(
                icon: Icons.workspace_premium_rounded,
                title: 'Unlock Pro',
                subtitle: 'More tracks and advanced workflow tools',
                onTap: () => _showComingSoon(context, 'Unlock Pro'),
              ),
              _ActionRow(
                icon: Icons.restore_rounded,
                title: 'Restore Purchases',
                subtitle: 'Restore previously unlocked entitlements',
                onTap: () => _showComingSoon(context, 'Restore Purchases'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SectionCard(
            title: 'Help',
            subtitle: 'Quick guidance for live looping workflow.',
            children: [
              _ActionRow(
                icon: Icons.help_outline_rounded,
                title: 'How It Works',
                subtitle: 'Core recording and track workflow',
                onTap: () => _showHowItWorks(context),
              ),
              _ActionRow(
                icon: Icons.settings_suggest_rounded,
                title: 'Feature Guide',
                subtitle: 'What each button and mode does',
                onTap: () => _showComingSoon(context, 'Feature Guide'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context, String name) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$name is coming soon.')));
  }

  Future<void> _showHowItWorks(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('How It Works'),
          content: const SingleChildScrollView(
            child: Text(
              '1) Choose BPM and the number of tracks to capture.\n\n'
              '2) Arm recording and play the first loop.\n\n'
              '3) Each track captures one loop and can be mixed individually.\n\n'
              '4) Use send controls (DLY/REV) and mixer levels to shape your sound.\n\n'
              '5) Use mute in track view or mixer level control to silence tracks quickly.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
