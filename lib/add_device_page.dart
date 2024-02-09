import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koshian5_tentomushi_mesh/bluetooth_provider.dart';
import 'package:koshian5_tentomushi_mesh/consts.dart';

class AddDevicePage extends ConsumerStatefulWidget {
  const AddDevicePage({super.key});

  @override
  ConsumerState<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends ConsumerState<AddDevicePage> {
  late BleScannedDeviceNotifier _bleScannedDeviceNotifier;

  @override
  void initState() {
    super.initState();
    _bleScannedDeviceNotifier = ref.read(bleScannerProvider.notifier);
    Future.delayed(Duration.zero, () async {
      _bleScannedDeviceNotifier.scanStart();
    });
  }

  @override
  void dispose() {
    super.dispose();
    Future.delayed(Duration.zero, () async {
      _bleScannedDeviceNotifier.scanStop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scannedDeviceList = ref.watch(bleScannerProvider).where((device) {
      return device.serviceUuids.contains(Uuid.parse(konashiSettingsServiceUuid));
    });
    final deviceSetupState = ref.watch(koshianMeshSetupProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("テントウムシを追加"),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: scannedDeviceList.map((e) {
            return InkWell(
                onTap: deviceSetupState != KoshianMeshSetupState.ready ? null : () async {
                  _bleScannedDeviceNotifier.scanStop();
                  await ref.read(koshianMeshSetupProvider.notifier).setup(e);
                  _bleScannedDeviceNotifier.scanStart();
                },
                child: Container(
                    padding: const EdgeInsets.fromLTRB(24+10.0, 15.0, 10.0, 15.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Mac: ${e.id}"),
                        Text("Name: ${e.name}"),
                        Text("RSSI: ${e.rssi}"),
                        Text("Connectable: ${e.connectable}"),
                        Text("Service UUIDs: ${e.serviceUuids}"),
                        Text("Service data: ${e.serviceData}"),
                        Text("Manufacturer data: ${e.manufacturerData}"),
                      ],
                    )
                )
            );
          }).toList()
        )
      ),
    );
  }
}
