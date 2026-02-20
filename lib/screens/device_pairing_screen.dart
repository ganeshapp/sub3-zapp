import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_provider.dart';
import '../services/ble_service.dart';

class DevicePairingScreen extends ConsumerStatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  ConsumerState<DevicePairingScreen> createState() =>
      _DevicePairingScreenState();
}

class _DevicePairingScreenState extends ConsumerState<DevicePairingScreen> {
  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    BleService.instance.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    try {
      await BleService.instance.startScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adapterState = ref.watch(bleAdapterStateProvider);
    final isScanning = ref.watch(bleScanningProvider).valueOrNull ?? false;
    final scanResults = ref.watch(bleScanResultsProvider).valueOrNull ?? [];
    final devices = ref.watch(connectedDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair Devices'),
        actions: [
          if (isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startScan,
            ),
        ],
      ),
      body: adapterState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Bluetooth error: $e')),
        data: (state) {
          if (state != BluetoothAdapterState.on) {
            return _BluetoothOffView(adapterState: state);
          }
          return _buildBody(theme, scanResults, devices, isScanning);
        },
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    List<ScanResult> scanResults,
    ConnectedDevicesState devices,
    bool isScanning,
  ) {
    // Filter to recognized FTMS / HR devices only.
    final recognized = <(ScanResult, BleDeviceRole)>[];
    for (final r in scanResults) {
      final role = BleService.classifyDevice(r);
      if (role != null) recognized.add((r, role));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ConnectedDeviceCard(
          label: 'Treadmill (FTMS)',
          icon: Icons.directions_run,
          device: devices.treadmill,
          connectionState: devices.treadmillState,
          isConnecting: devices.isConnectingTreadmill,
          onDisconnect: () => ref
              .read(connectedDevicesProvider.notifier)
              .disconnectDevice(BleDeviceRole.treadmill),
        ),
        const SizedBox(height: 10),
        _ConnectedDeviceCard(
          label: 'Heart Rate Sensor',
          icon: Icons.favorite,
          device: devices.hrSensor,
          connectionState: devices.hrSensorState,
          isConnecting: devices.isConnectingHr,
          onDisconnect: () => ref
              .read(connectedDevicesProvider.notifier)
              .disconnectDevice(BleDeviceRole.heartRate),
        ),
        const SizedBox(height: 24),
        Text(
          'DISCOVERED DEVICES',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
        ),
        const SizedBox(height: 10),
        if (recognized.isEmpty && !isScanning)
          _EmptyScanView(onRescan: _startScan),
        if (recognized.isEmpty && isScanning)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Scanning for devices...'),
                ],
              ),
            ),
          ),
        for (final (result, role) in recognized)
          _ScanResultTile(
            result: result,
            role: role,
            isAlreadyConnected: _isAlreadyConnected(result.device, devices),
            onConnect: () => _connectDevice(result.device, role),
          ),
      ],
    );
  }

  bool _isAlreadyConnected(BluetoothDevice device, ConnectedDevicesState d) {
    return d.treadmill?.remoteId == device.remoteId ||
        d.hrSensor?.remoteId == device.remoteId;
  }

  Future<void> _connectDevice(BluetoothDevice device, BleDeviceRole role) async {
    try {
      await ref
          .read(connectedDevicesProvider.notifier)
          .connectDevice(device, role);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${role == BleDeviceRole.treadmill ? "Treadmill" : "HR Sensor"} connected'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }
}

// ── Sub-widgets ──

class _BluetoothOffView extends StatelessWidget {
  final BluetoothAdapterState adapterState;
  const _BluetoothOffView({required this.adapterState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 64,
                color: theme.colorScheme.error.withValues(alpha: 0.6)),
            const SizedBox(height: 20),
            Text('Bluetooth is ${adapterState.name}',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Please enable Bluetooth in your device settings to scan for fitness equipment.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedDeviceCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final BluetoothDevice? device;
  final BluetoothConnectionState connectionState;
  final bool isConnecting;
  final VoidCallback onDisconnect;

  const _ConnectedDeviceCard({
    required this.label,
    required this.icon,
    required this.device,
    required this.connectionState,
    required this.isConnecting,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = connectionState == BluetoothConnectionState.connected;

    final Color statusColor;
    final String statusText;
    if (isConnecting) {
      statusColor = Colors.amber;
      statusText = 'Connecting...';
    } else if (connected && device != null) {
      statusColor = Colors.green;
      statusText = device!.platformName.isNotEmpty
          ? device!.platformName
          : device!.remoteId.str;
    } else {
      statusColor = Colors.grey;
      statusText = 'Not connected';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: connected
            ? Border.all(color: Colors.green.withValues(alpha: 0.4), width: 1)
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.titleLarge?.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(statusText, style: theme.textTheme.bodyMedium?.copyWith(
                  color: statusColor,
                  fontSize: 13,
                )),
              ],
            ),
          ),
          if (isConnecting)
            const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (connected)
            IconButton(
              icon: const Icon(Icons.link_off, size: 20),
              color: Colors.red.shade400,
              onPressed: onDisconnect,
              tooltip: 'Disconnect',
            )
          else
            Icon(Icons.bluetooth_disabled, color: Colors.grey.shade600, size: 20),
        ],
      ),
    );
  }
}

class _ScanResultTile extends StatelessWidget {
  final ScanResult result;
  final BleDeviceRole role;
  final bool isAlreadyConnected;
  final VoidCallback onConnect;

  const _ScanResultTile({
    required this.result,
    required this.role,
    required this.isAlreadyConnected,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : result.device.remoteId.str;
    final roleLabel =
        role == BleDeviceRole.treadmill ? 'FTMS Treadmill' : 'Heart Rate';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              role == BleDeviceRole.treadmill
                  ? Icons.directions_run
                  : Icons.favorite,
              color: Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleLarge?.copyWith(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    '$roleLabel  •  RSSI ${result.rssi} dBm',
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isAlreadyConnected)
              const Icon(Icons.check_circle, color: Colors.green, size: 22)
            else
              SizedBox(
                height: 32,
                child: FilledButton(
                  onPressed: onConnect,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('Pair'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyScanView extends StatelessWidget {
  final VoidCallback onRescan;
  const _EmptyScanView({required this.onRescan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.bluetooth_searching, size: 48,
                color: theme.colorScheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No devices found', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Make sure your treadmill and HR sensor\nare powered on and in pairing mode.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRescan,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Scan Again'),
            ),
          ],
        ),
      ),
    );
  }
}
