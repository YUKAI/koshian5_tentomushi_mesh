import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koshian5_tentomushi_mesh/debug.dart';
import 'package:permission_handler/permission_handler.dart';

// ------------------------------------------------------------------------------------
// - Bluetooth state provider.

class BluetoothAdapterStateNotifier
    extends StateNotifier<BleStatus> {
  final Ref ref;

  BluetoothAdapterStateNotifier(this.ref)
      : super(BleStatus.unknown);

  StreamSubscription<BleStatus>? _adapterStateListener;
  Completer<bool> _stateCompleter = Completer();
  void _adapterStateCallback(event) {
    logger.d("BLE state event: $event");
    state = event;
    if (event == BleStatus.ready) {
      _stateCompleter.complete(true);
    }
  }

  Future<bool> init() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    logger.d("Permissions: $statuses");
    if (!statuses.values.every((v) => v == PermissionStatus.granted)) {
      return false;
    }
    _adapterStateListener ??=
        FlutterReactiveBle().statusStream.listen(_adapterStateCallback);
    if (state != BleStatus.ready) {
      _stateCompleter = Completer();
      try {
        return await _stateCompleter.future.timeout(const Duration(seconds: 5));
      } on TimeoutException catch (e) {
        logger.d('Bluetooth init timeout occurred: $e');
        return false;
      }
    }
    return true;
  }
}

final bluetoothInitProvider =
    StateNotifierProvider<BluetoothAdapterStateNotifier, BleStatus>(
        (ref) {
  var inst = BluetoothAdapterStateNotifier(ref);
  return inst;
});
