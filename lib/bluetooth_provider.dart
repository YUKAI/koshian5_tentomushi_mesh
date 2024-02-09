import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koshian5_tentomushi_mesh/debug.dart';
import 'package:nordic_nrf_mesh/nordic_nrf_mesh.dart';
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


// ------------------------------------------------------------------------------------
// - Mesh entry point.

final nordicNrfMesh = NordicNrfMesh();


// ------------------------------------------------------------------------------------
// - Mesh network provider.

class MeshNetworkNotifier extends StateNotifier<IMeshNetwork?> {
  final Ref ref;

  MeshNetworkNotifier(this.ref) : super(null) {
    nordicNrfMesh.meshManagerApi.loadMeshNetwork().then((network) {
      state = network;
    });
  }
}

final meshNetworkProvider = StateNotifierProvider<MeshNetworkNotifier, IMeshNetwork?>((ref) {
  var inst = MeshNetworkNotifier(ref);
  return inst;
});


// ------------------------------------------------------------------------------------
// - Mesh network key provider.

class MeshNetworkKeyNotifier extends StateNotifier<NetworkKey?> {
  final Ref ref;

  MeshNetworkKeyNotifier(this.ref) : super(null) {
    ref.listen(meshNetworkProvider, (previous, next) async {
      if (next != null) {
        state = await next.getNetKey(0);
        state ??= await next.generateNetKey();
      }
    });
  }
}

final meshNetworkKeyProvider = StateNotifierProvider<MeshNetworkKeyNotifier, NetworkKey?>((ref) {
  var inst = MeshNetworkKeyNotifier(ref);
  return inst;
});


// ------------------------------------------------------------------------------------
// - Bluetooth scan state provider.

class BleScannedDevice {
  final String id;
  String _name;
  String get name => _name;
  final Map<Uuid, Uint8List> _serviceData;
  Map<Uuid, Uint8List> get serviceData => _serviceData;
  List<Uuid> _serviceUuids;
  List<Uuid> get serviceUuids => _serviceUuids;
  final List<Uint8List> _manufacturerData;
  List<Uint8List> get manufacturerData => _manufacturerData;
  int _rssi;
  int get rssi => _rssi;
  Connectable _connectable;
  Connectable get connectable => _connectable;

  BleScannedDevice(DiscoveredDevice discoveredDevice) :
    id = discoveredDevice.id,
    _name = discoveredDevice.name,
    _serviceData = discoveredDevice.serviceData,
    _serviceUuids = discoveredDevice.serviceUuids.toList(),
    _manufacturerData = discoveredDevice.manufacturerData.length >= 2 ? [discoveredDevice.manufacturerData] : [],
    _rssi = discoveredDevice.rssi,
    _connectable = discoveredDevice.connectable
  ;

  void updateDevice(DiscoveredDevice updatedDevice) {
    if (id != updatedDevice.id) {
      return;
    }
    if (updatedDevice.name.isNotEmpty) {
      _name = updatedDevice.name;
    }
    updatedDevice.serviceData.forEach((key, value) {
      _serviceData[key] = value;
    });
    if (updatedDevice.manufacturerData.length >= 2) {
      var newManufacturerId = updatedDevice.manufacturerData[0] + (updatedDevice.manufacturerData[1]<<8);
      bool hasManufacturerId = false;
      for (var i=0; i<_manufacturerData.length; i++) {
        var manufacturerId = _manufacturerData[i][0] + (_manufacturerData[i][1]<<8);
        if (newManufacturerId == manufacturerId) {
          _manufacturerData[i] = updatedDevice.manufacturerData;
          hasManufacturerId = true;
        }
      }
      if (!hasManufacturerId) {
        _manufacturerData.add(updatedDevice.manufacturerData);
      }
    }
    _rssi = updatedDevice.rssi;
    for (var value in updatedDevice.serviceUuids) {
      if (!_serviceUuids.contains(value)) {
        _serviceUuids.add(value);
      }
    }
    _connectable = _connectable != Connectable.available ? updatedDevice.connectable : Connectable.available;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is BleScannedDevice &&
              runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class BleScannedDeviceNotifier extends StateNotifier<List<BleScannedDevice>> {
  final Ref ref;

  BleScannedDeviceNotifier(this.ref) : super([]);

  StreamSubscription<DiscoveredDevice>? _scanListener;

  Future<bool> scanStart() async {
    if (_scanListener != null) {
      return true;
    }
    var isOn = await ref.read(bluetoothInitProvider.notifier).init();
    if (!isOn) {
      return false;
    }
    _scanListener = FlutterReactiveBle().scanForDevices(
      withServices: []
    ).listen((result) {
      BleScannedDevice c = BleScannedDevice(result);
      var i = state.indexOf(c);
      if (i > -1) {
        state[i].updateDevice(result);
      } else {
        state.add(c);
      }
      state = [...state];
    });
    return true;
  }

  void scanStop() async {
    await _scanListener?.cancel();
    _scanListener = null;
    state = [];
  }
}

final bleScannerProvider = StateNotifierProvider<BleScannedDeviceNotifier, List<BleScannedDevice>>((ref) {
  var inst = BleScannedDeviceNotifier(ref);
  return inst;
});
