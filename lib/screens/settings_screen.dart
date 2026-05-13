import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../constants/app_theme.dart';
import '../widgets/feature_guide_dialog.dart';

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
            title: 'Appearance',
            subtitle: 'Choose a color palette for the UI',
            children: [
              const _PaletteSelector(),
            ],
          ),
          const SizedBox(height: 10),
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
                onTap: () => _showFeatureGuide(context),
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

  Future<void> _showFeatureGuide(BuildContext context) async {
    // Defer to the feature guide markdown dialog.
    // Implemented in lib/widgets/feature_guide_dialog.dart
    try {
      // Import here to keep top-level imports tidy and avoid unused warnings
      // when the guide isn't used in some builds.
      await FeatureGuideDialog.show(context);
    } catch (e) {
      _showComingSoon(context, 'Feature Guide');
    }
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

class _PaletteSelector extends StatelessWidget {
  const _PaletteSelector();

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final current = themeProvider.palette;

    return Column(
      children: AppPalette.values.map((p) {
        final label = _labelFor(p);
        return RadioListTile<AppPalette>(
          value: p,
          groupValue: current,
          title: Text(label),
          secondary: _previewFor(p),
          onChanged: (v) {
            if (v != null) themeProvider.setPalette(v);
          },
        );
      }).toList(),
    );
  }

  String _labelFor(AppPalette p) {
    switch (p) {
      case AppPalette.neonGreen:
        return 'Neon Green';
      case AppPalette.neonYellow:
        return 'Neon Yellow';
      case AppPalette.neonRed:
        return 'Neon Red';
      case AppPalette.light:
        return 'Light';
      case AppPalette.neonBlue:
        return 'Neon Blue';
    }
  }

  Widget _previewFor(AppPalette p) {
    // Small color swatch preview
    final theme = AppTheme.themeFor(p);
    final primary = theme.colorScheme.primary;
    final secondary = theme.colorScheme.secondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 18, height: 18, color: primary),
        const SizedBox(width: 6),
        Container(width: 18, height: 18, color: secondary),
      ],
    );
  }
}
