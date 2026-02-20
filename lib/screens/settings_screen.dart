import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/ble_provider.dart';
import '../services/ble_service.dart';
import '../services/strava_service.dart';
import 'about_screen.dart';
import 'device_pairing_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _stravaLinked = false;
  bool _checkingStrava = true;
  double? _heightCm;
  double? _weightKg;

  static const _keyHeight = 'profile_height_cm';
  static const _keyWeight = 'profile_weight_kg';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final linked = await StravaService.isLinked;
    if (!mounted) return;
    setState(() {
      _heightCm = prefs.getDouble(_keyHeight);
      _weightKg = prefs.getDouble(_keyWeight);
      _stravaLinked = linked;
      _checkingStrava = false;
    });
  }

  Future<void> _toggleStrava(bool enable) async {
    if (enable) {
      await StravaService.launchOAuth();
      Future.delayed(const Duration(seconds: 2), () async {
        final linked = await StravaService.isLinked;
        if (mounted) setState(() => _stravaLinked = linked);
      });
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          title: const Text('Unlink Strava?'),
          content: const Text('You can re-link at any time.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Unlink'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await StravaService.clearTokens();
        setState(() => _stravaLinked = false);
      }
    }
  }

  Future<void> _editHeight() async {
    final result = await _showNumberInput(
      title: 'Height',
      unit: 'cm',
      current: _heightCm,
      min: 100,
      max: 250,
    );
    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyHeight, result);
      setState(() => _heightCm = result);
    }
  }

  Future<void> _editWeight() async {
    final result = await _showNumberInput(
      title: 'Weight',
      unit: 'kg',
      current: _weightKg,
      min: 30,
      max: 200,
    );
    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyWeight, result);
      setState(() => _weightKg = result);
    }
  }

  Future<double?> _showNumberInput({
    required String title,
    required String unit,
    required double? current,
    required double min,
    required double max,
  }) async {
    final controller =
        TextEditingController(text: current?.toStringAsFixed(1) ?? '');
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text('Set $title'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            suffixText: unit,
            hintText: 'Enter $title',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val >= min && val <= max) {
                Navigator.pop(ctx, val);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = ref.watch(connectedDevicesProvider);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Devices ──
        _SettingsSection(
          title: 'Devices',
          children: [
            _DeviceTile(
              icon: Icons.directions_run,
              label: 'Treadmill',
              device: devices.treadmill,
              state: devices.treadmillState,
              isConnecting: devices.isConnectingTreadmill,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const DevicePairingScreen()),
              ),
              onDisconnect: () => ref
                  .read(connectedDevicesProvider.notifier)
                  .disconnectDevice(BleDeviceRole.treadmill),
            ),
            const Divider(height: 1, indent: 56),
            _DeviceTile(
              icon: Icons.favorite,
              label: 'HR Sensor',
              device: devices.hrSensor,
              state: devices.hrSensorState,
              isConnecting: devices.isConnectingHr,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const DevicePairingScreen()),
              ),
              onDisconnect: () => ref
                  .read(connectedDevicesProvider.notifier)
                  .disconnectDevice(BleDeviceRole.heartRate),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Account ──
        _SettingsSection(
          title: 'Account',
          children: [
            _SettingsTile(
              icon: Icons.sync_alt,
              title: 'Strava',
              subtitle: _checkingStrava
                  ? 'Checking...'
                  : _stravaLinked
                      ? 'Linked'
                      : 'Not linked',
              trailing: _checkingStrava
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch(
                      value: _stravaLinked,
                      onChanged: _toggleStrava,
                      activeColor: theme.colorScheme.primary,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Profile ──
        _SettingsSection(
          title: 'Profile',
          children: [
            _SettingsTile(
              icon: Icons.person_outline,
              title: 'Height',
              subtitle:
                  _heightCm != null ? '${_heightCm!.toStringAsFixed(1)} cm' : 'Tap to set',
              onTap: _editHeight,
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.monitor_weight_outlined,
              title: 'Weight',
              subtitle:
                  _weightKg != null ? '${_weightKg!.toStringAsFixed(1)} kg' : 'Tap to set',
              onTap: _editWeight,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── About ──
        _SettingsSection(
          title: 'About',
          children: [
            _SettingsTile(
              icon: Icons.info_outline,
              title: 'About Sub3',
              subtitle: 'v1.0.0',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.route,
              title: 'Workout Planner',
              subtitle: 'gapp.in/sub3',
              onTap: () => launchUrl(
                Uri.parse('https://www.gapp.in/sub3/'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.code,
              title: 'Developer',
              subtitle: 'gapp.in',
              onTap: () => launchUrl(
                Uri.parse('https://www.gapp.in'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Device tile with live connection status ──

class _DeviceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final BluetoothDevice? device;
  final BluetoothConnectionState state;
  final bool isConnecting;
  final VoidCallback onTap;
  final VoidCallback onDisconnect;

  const _DeviceTile({
    required this.icon,
    required this.label,
    required this.device,
    required this.state,
    required this.isConnecting,
    required this.onTap,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = state == BluetoothConnectionState.connected;

    final Color statusColor;
    final String subtitle;
    if (isConnecting) {
      statusColor = Colors.amber;
      subtitle = 'Connecting...';
    } else if (connected && device != null) {
      statusColor = Colors.green;
      final name = device!.platformName.isNotEmpty
          ? device!.platformName
          : device!.remoteId.str;
      subtitle = 'Connected · $name';
    } else {
      statusColor = Colors.grey;
      subtitle = 'Tap to pair';
    }

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: statusColor, size: 20),
      ),
      title: Text(label,
          style: theme.textTheme.titleLarge?.copyWith(fontSize: 16)),
      subtitle: Text(subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: statusColor,
            fontSize: 13,
          )),
      trailing: isConnecting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : connected
              ? IconButton(
                  icon: Icon(Icons.link_off,
                      size: 18, color: Colors.red.shade400),
                  onPressed: onDisconnect,
                )
              : const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
    );
  }
}

// ── Reusable section / tile widgets ──

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title,
          style: theme.textTheme.titleLarge?.copyWith(fontSize: 16)),
      subtitle: Text(subtitle, style: theme.textTheme.bodyMedium),
      trailing:
          trailing ?? const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
    );
  }
}
