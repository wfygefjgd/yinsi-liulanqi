import 'package:flutter/material.dart';

import 'privacy_engine.dart';

/// Shared dark palette (mirrors _S in privacy_browser_shell.dart).
class SettingsColors {
  static const bg = Color(0xFF000000);
  static const bar = Color(0xF01C1C1E);
  static const accent = Color(0xFF0A84FF);
  static const text = Color(0xFFFFFFFF);
  static const secondary = Color(0xFF8E8E93);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _keyAutoWipe = 'pref_auto_wipe_on_background';
  bool _autoWipe = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await PrivacyEngine.prefs();
    if (!mounted) return;
    setState(() {
      _autoWipe = prefs.getBool(_keyAutoWipe) ?? true;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _autoWipe = value);
    final prefs = await PrivacyEngine.prefs();
    await prefs.setBool(_keyAutoWipe, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SettingsColors.bg,
      appBar: AppBar(
        backgroundColor: SettingsColors.bar,
        foregroundColor: SettingsColors.text,
        title: const Text('设置'),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: SettingsColors.accent))
          : ListView(
              children: [
                const _SectionHeader(title: '隐私'),
                _SwitchTile(
                  icon: Icons.shield_outlined,
                  title: '退到后台时自动清理',
                  subtitle: _autoWipe
                      ? '离开浏览器时自动清除所有数据并冷启动'
                      : '关闭后表现为正常浏览器，保留数据',
                  value: _autoWipe,
                  onChanged: _toggle,
                ),
                const _SectionHeader(title: '关于'),
                const _InfoTile(
                  icon: Icons.info_outline,
                  title: '版本',
                  subtitle: '1.0.21',
                ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: SettingsColors.secondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: SettingsColors.accent),
      title: Text(title, style: const TextStyle(color: SettingsColors.text, fontSize: 16)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          subtitle,
          style: const TextStyle(color: SettingsColors.secondary, fontSize: 13),
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: SettingsColors.accent,
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: SettingsColors.accent),
      title: Text(title, style: const TextStyle(color: SettingsColors.text, fontSize: 16)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          subtitle,
          style: const TextStyle(color: SettingsColors.secondary, fontSize: 13),
        ),
      ),
    );
  }
}
