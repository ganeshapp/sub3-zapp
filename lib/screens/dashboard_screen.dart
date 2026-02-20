import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final devices = ref.watch(connectedDevicesProvider);

    final tmConnected =
        devices.treadmillState == BluetoothConnectionState.connected;
    final hrConnected =
        devices.hrSensorState == BluetoothConnectionState.connected;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          _DeviceStatusCard(
            icon: Icons.directions_run,
            title: 'Treadmill',
            subtitle: tmConnected
                ? (devices.treadmill?.platformName ?? 'Connected')
                : devices.isConnectingTreadmill
                    ? 'Connecting...'
                    : 'Not connected',
            statusColor: tmConnected
                ? Colors.green
                : devices.isConnectingTreadmill
                    ? Colors.amber
                    : Colors.grey,
            trailingIcon: tmConnected
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
          ),
          const SizedBox(height: 12),
          _DeviceStatusCard(
            icon: Icons.favorite,
            title: 'Heart Rate Sensor',
            subtitle: hrConnected
                ? (devices.hrSensor?.platformName ?? 'Connected')
                : devices.isConnectingHr
                    ? 'Connecting...'
                    : 'Not connected',
            statusColor: hrConnected
                ? Colors.green
                : devices.isConnectingHr
                    ? Colors.amber
                    : Colors.grey,
            trailingIcon: hrConnected
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
          ),
          const Spacer(),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.play_circle_outline,
                  size: 80,
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Select a workout from the Library\nand pair your devices to begin.',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _DeviceStatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color statusColor;
  final IconData trailingIcon;

  const _DeviceStatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.statusColor,
    required this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: statusColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(
                  color: statusColor,
                )),
              ],
            ),
          ),
          Icon(trailingIcon, color: statusColor.withValues(alpha: 0.6), size: 20),
        ],
      ),
    );
  }
}
