import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koshian5_tentomushi_mesh/bluetooth_provider.dart';
import 'package:koshian5_tentomushi_mesh/consts.dart';
import 'package:koshian5_tentomushi_mesh/debug.dart';

class AddDevicePage extends ConsumerStatefulWidget {
  const AddDevicePage({super.key});

  @override
  ConsumerState<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends ConsumerState<AddDevicePage> {
  late BleScannedDeviceNotifier _bleScannedDeviceNotifier;
  final stepToText = {
    KoshianMeshSetupState.ready: "待機",
    KoshianMeshSetupState.connecting: "接続中",
    KoshianMeshSetupState.koshianSettings: "Koshian設定",
    KoshianMeshSetupState.unprovisionedScan: "Meshスキャン",
    KoshianMeshSetupState.provisioning: "プロビジョニング",
    KoshianMeshSetupState.meshSettings: "Mesh設定",
  };

  @override
  void initState() {
    super.initState();
    _bleScannedDeviceNotifier = ref.read(bleScannerProvider.notifier);
    Future(() async {
      await ref.read(koshianMeshProxyProvider.notifier).disconnect();
      logger.d("Disconnected from proxy");
      await _bleScannedDeviceNotifier.scanStart();
      logger.d("Scan started");
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
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24+10.0, 15.0, 10.0, 15.0),
              child: Text("追加ステップ：${stepToText[deviceSetupState]}")
            ),
            const Divider(height: 4, thickness: 3, indent: 0, endIndent: 0),
            ...scannedDeviceList.map((e) {
              var canTap = deviceSetupState == KoshianMeshSetupState.ready  &&
                  ref.read(koshianNodeListProvider).indexWhere((element) => element.name == e.name) < 0;
              return InkWell(
                  onTap: canTap ? () async {
                    _bleScannedDeviceNotifier.scanStop();
                    await ref.read(koshianMeshSetupProvider.notifier).setup(e);
                    _bleScannedDeviceNotifier.scanStart();
                  } : null,
                  child: Container(
                      padding: const EdgeInsets.fromLTRB(24+10.0, 15.0, 10.0, 15.0),
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Mac: ${e.id}\r\n"
                            "Name: ${e.name}\r\n"
                            "RSSI: ${e.rssi}\r\n"
                            "Connectable: ${e.connectable}\r\n"
                            "Service UUIDs: ${e.serviceUuids}\r\n"
                            "Service data: ${e.serviceData}\r\n"
                            "Manufacturer data: ${e.manufacturerData}",
                            style: TextStyle(
                              color: canTap ? Colors.black : Colors.grey,
                            ),
                          ),
                        ],
                      )
                  )
              );
            })
          ]
        )
      ),
    );
  }
}
