import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koshian5_tentomushi_mesh/consts.dart';
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
      if (!_stateCompleter.isCompleted) {
        _stateCompleter.complete(true);
      }
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

  Future<void> reload() async {
    state = null;
    state = await nordicNrfMesh.meshManagerApi.loadMeshNetwork();
  }

  Future<void> reset() async {
    state = null;
    await nordicNrfMesh.meshManagerApi.resetMeshNetwork();
    state = await nordicNrfMesh.meshManagerApi.loadMeshNetwork();
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
  final List<Uuid> _serviceUuids;
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


// ------------------------------------------------------------------------------------
// - Koshian device mesh setup provider.

enum KoshianMeshSetupState {
  ready,
  connecting,
  koshianSettings,
  unprovisionedScan,
  provisioning,
  meshSettings,
}

class KoshianMeshSetupNotifier extends StateNotifier<KoshianMeshSetupState> {
  final Ref ref;

  KoshianMeshSetupNotifier(this.ref) : super(KoshianMeshSetupState.ready);

  Future<bool> setup(BleScannedDevice device) async {
    bool ret = false;
    for (var tries=0; tries<3; tries++) {
      ret = await _setupTry(device);
      if (ret == true) {
        break;
      }
    }
    return ret;
  }

  Future<bool> _setupTry(BleScannedDevice device) async {
    if (state != KoshianMeshSetupState.ready) {
      logger.w("Device setup already ongoing");
      return false;
    }
    logger.i("Attempt device setup");
    // connect
    state = KoshianMeshSetupState.connecting;
    final connectionCompleter = Completer<bool>();
    StreamSubscription<ConnectionStateUpdate>? connectionListener;
    final unprovisionedScanCompleter = Completer<DiscoveredDevice?>();
    StreamSubscription<DiscoveredDevice>? unprovisionedScanListener;
    try {
      connectionListener = FlutterReactiveBle().connectToAdvertisingDevice(
        id: device.id,
        withServices: [],
        prescanDuration: const Duration(seconds: 10)
      ).listen((connection) {
        if (connection.connectionState == DeviceConnectionState.connected) {
          connectionCompleter.complete(true);
        }
      });
      if (!await connectionCompleter.future.timeout(const Duration(seconds: 12), onTimeout: () => false)) {
        throw "Connection error";
      }
      FlutterReactiveBle().discoverAllServices(device.id);
      state = KoshianMeshSetupState.koshianSettings;
      final settingsCmdC12c = QualifiedCharacteristic(
          serviceId: Uuid.parse(konashiSettingsServiceUuid),
          characteristicId: Uuid.parse(konashiSettingsCommandC12cUuid),
          deviceId: device.id
      );
      final systemSettingsC12c = QualifiedCharacteristic(
          serviceId: Uuid.parse(konashiSettingsServiceUuid),
          characteristicId: Uuid.parse(konashiSystemSettingsGetC12cUuid),
          deviceId: device.id
      );
      final bluetoothSettingsC12c = QualifiedCharacteristic(
          serviceId: Uuid.parse(konashiSettingsServiceUuid),
          characteristicId: Uuid.parse(konashiBluetoothSettingsGetC12cUuid),
          deviceId: device.id
      );
      final configCmdC12c = QualifiedCharacteristic(
          serviceId: Uuid.parse(konashiConfigServiceUuid),
          characteristicId: Uuid.parse(konashiConfigCommandC12cUuid),
          deviceId: device.id
      );
      // enable NVM
      FlutterReactiveBle().subscribeToCharacteristic(systemSettingsC12c).listen((data) {
        logger.i("System settings update: $data");
      });
      await FlutterReactiveBle().writeCharacteristicWithResponse(settingsCmdC12c, value: [0x01,0x01,0x01]);
      // enable mesh
      var bluetoothSettings = await FlutterReactiveBle().readCharacteristic(bluetoothSettingsC12c);
      if (bluetoothSettings[0] & 0x01 == 0) {  // Mesh disabled
        FlutterReactiveBle().subscribeToCharacteristic(bluetoothSettingsC12c).listen((data) {
          logger.i("Bluetooth settings update: $data");
        });
        await FlutterReactiveBle().writeCharacteristicWithResponse(settingsCmdC12c, value: [0x02,0x01]);
      }
      else {
        logger.i("Bluetooth Mesh already enabled");
      }
      await FlutterReactiveBle().writeCharacteristicWithResponse(configCmdC12c, value: [0x03, 0xff,0x00,0x00,0x4b]);
      await FlutterReactiveBle().writeCharacteristicWithResponse(configCmdC12c, value: [0x03, 0x01]);
      await FlutterReactiveBle().writeCharacteristicWithResponse(configCmdC12c, value: [0x01, 0x11,0x10, 0x61,0x10, 0x71,0x10]);
      await connectionListener.cancel();
      state = KoshianMeshSetupState.unprovisionedScan;
      unprovisionedScanListener = nordicNrfMesh.scanForUnprovisionedNodes().listen((scannedDevice) {
        if (device.id == scannedDevice.id  &&  scannedDevice.serviceData.containsKey(meshProvisioningUuid)) {
          unprovisionedScanCompleter.complete(scannedDevice);
        }
      });
      var unprovisionedDevice = await unprovisionedScanCompleter.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
      if (unprovisionedDevice == null) {
        throw "Unprovisioned scan error";
      }
      await unprovisionedScanListener.cancel();
      final deviceUuid = Uuid.parse(
          nordicNrfMesh.meshManagerApi.getDeviceUuid(
              unprovisionedDevice.serviceData[meshProvisioningUuid]!.toList()
          )
      ).toString();
      logger.i("Device UUID: $deviceUuid");
      state = KoshianMeshSetupState.provisioning;
      final provisioningEvent = ProvisioningEvent();
      provisioningEvent.onProvisioning.listen((event) {
        logger.i("onProvisioning $event");
      });
      provisioningEvent.onProvisioningCapabilities.listen((event) {
        logger.i("onProvisioningCapabilities $event");
      });
      provisioningEvent.onProvisioningInvitation.listen((event) {
        logger.i("onProvisioningInvitation $event");
      });
      provisioningEvent.onProvisioningReconnect.listen((event) {
        logger.i("onProvisioningReconnect $event");
      });
      provisioningEvent.onConfigCompositionDataStatus.listen((event) {
        logger.i("onConfigCompositionDataStatus $event");
      });
      provisioningEvent.onConfigAppKeyStatus.listen((event) {
        logger.i("onConfigAppKeyStatus $event");
      });
      provisioningEvent.onProvisioningGattError.listen((event) {
        logger.i("onProvisioningGattError $event");
      });
      var provisionedNode = await nordicNrfMesh.provisioning(
          nordicNrfMesh.meshManagerApi,
          BleMeshManager(),
          unprovisionedDevice,
          deviceUuid,
          events: provisioningEvent,
      ).timeout(const Duration(minutes: 1));
      logger.i("Provisioned node: $provisionedNode");
      provisionedNode.nodeName = device.name;
      await ref.read(meshNetworkProvider.notifier).reload();
      state = KoshianMeshSetupState.meshSettings;
      await BleMeshManager().disconnect();
      var proxyConnectResult = await ref.read(koshianMeshProxyProvider.notifier).connect(
        specificDevice: unprovisionedDevice,
        scanTimeout: const Duration(seconds: 20),
        forceReconnect: true,
      );
      if (proxyConnectResult == false) {
        throw "Could not connect to proxy (${ref.read(koshianMeshProxyProvider.notifier).latestError})";
      }
      var nodeUnicastAddress = await provisionedNode.unicastAddress;
      ConfigModelAppStatusData configModelAppBindResult;
      configModelAppBindResult = await nordicNrfMesh.meshManagerApi.sendConfigModelAppBind(
          nodeUnicastAddress,
          nodeUnicastAddress+1,
          0x1002
      );
      logger.d("App bind PIO0 level result: $configModelAppBindResult");
      configModelAppBindResult = await nordicNrfMesh.meshManagerApi.sendConfigModelAppBind(
          nodeUnicastAddress,
          nodeUnicastAddress+2,
          0x1000
      );
      logger.d("App bind PIO1 level result: $configModelAppBindResult");
      configModelAppBindResult = await nordicNrfMesh.meshManagerApi.sendConfigModelAppBind(
          nodeUnicastAddress,
          nodeUnicastAddress+7,
          0x1000
      );
      logger.d("App bind PIO6 level result: $configModelAppBindResult");
      configModelAppBindResult = await nordicNrfMesh.meshManagerApi.sendConfigModelAppBind(
          nodeUnicastAddress,
          nodeUnicastAddress+8,
          0x1000
      );
      logger.d("App bind PIO7 level result: $configModelAppBindResult");
      await ref.read(koshianMeshProxyProvider.notifier).disconnect();
      state = KoshianMeshSetupState.ready;
      logger.i("Device setup done");
    }
    catch (e, s) {
      logger.i("Failed: $e\r\n$s");
      await unprovisionedScanListener?.cancel();
      await connectionListener?.cancel();
      nordicNrfMesh.cancelProvisioning(nordicNrfMesh.meshManagerApi, BleMeshManager());
      state = KoshianMeshSetupState.ready;
      return false;
    }
    return true;
  }
}

final koshianMeshSetupProvider = StateNotifierProvider<KoshianMeshSetupNotifier, KoshianMeshSetupState>((ref) {
  var inst = KoshianMeshSetupNotifier(ref);
  return inst;
});


// ------------------------------------------------------------------------------------
// - Koshian device mesh proxy provider.

enum KoshianMeshProxyState {
  disconnected,
  connecting,
  connected,
  error,
}

class _BleMeshManagerProxyCallbacks extends BleMeshManagerCallbacks {
  final MeshManagerApi meshManagerApi;

  /// {@macro prov_ble_manager}
  _BleMeshManagerProxyCallbacks(this.meshManagerApi);

  @override
  Future<void> sendMtuToMeshManagerApi(int mtu) => meshManagerApi.setMtu(mtu);
}

class KoshianMeshProxyNotifier extends StateNotifier<KoshianMeshProxyState> {
  final Ref ref;

  StreamSubscription<DiscoveredDevice>? _proxyScanListener;
  Completer<DiscoveredDevice?>? _proxyScanCompleter;
  StreamSubscription<List<int>>? _onMeshPduCreatedSubscription;
  StreamSubscription<BleMeshManagerCallbacksDataSent>? _onDataSentSubscription;
  StreamSubscription<BleMeshManagerCallbacksDataReceived>? _onDataReceivedSubscription;
  StreamSubscription<ConnectionStateUpdate>? _onDeviceDisconnectedSubscription;

  KoshianMeshProxyNotifier(this.ref) : super(KoshianMeshProxyState.disconnected);

  String _latestError = "";
  String get latestError => state == KoshianMeshProxyState.error ? _latestError : "";

  void _clearSubscriptions() {
    _onMeshPduCreatedSubscription?.cancel();
    _onMeshPduCreatedSubscription = null;
    _onDataSentSubscription?.cancel();
    _onDataSentSubscription = null;
    _onDataReceivedSubscription?.cancel();
    _onDataReceivedSubscription = null;
    _onDeviceDisconnectedSubscription?.cancel();
    _onDeviceDisconnectedSubscription = null;
  }

  Future<bool> connect({
    Duration? scanTimeout,
    DiscoveredDevice? specificDevice,
    bool forceReconnect = false,
  }) async {
    try {
      if (!forceReconnect && (state == KoshianMeshProxyState.connecting || state == KoshianMeshProxyState.connected)) {
        logger.d("Already connecting or connected to proxy, no forced reconnect");
        return true;
      }
      state = KoshianMeshProxyState.connecting;
      if (forceReconnect && (state == KoshianMeshProxyState.connecting || state == KoshianMeshProxyState.connected)) {
        logger.d("Forced reconnect, disconnect or cancel first");
        await disconnect();
      }
      logger.d("Attempt proxy connect (specific device: $specificDevice, timeout: $scanTimeout)");
      _proxyScanCompleter = Completer<DiscoveredDevice?>();
      _proxyScanListener = nordicNrfMesh.scanForProxy().listen((scannedDevice) {
        logger.i("Proxy scanned device: $scannedDevice");
        if (scannedDevice.serviceData.containsKey(meshProxyUuid)) {
          if (specificDevice != null  &&  specificDevice.id != scannedDevice.id) {
            return;
          }
          logger.i("Proxy found device: $scannedDevice");
          _proxyScanCompleter?.complete(scannedDevice);
        }
      });
      var proxyDevice = scanTimeout == null ? await _proxyScanCompleter?.future :
          await _proxyScanCompleter?.future.timeout(scanTimeout, onTimeout: () => null);
      _proxyScanCompleter = null;
      await _proxyScanListener?.cancel();
      if (proxyDevice == null) {
        if (_proxyScanListener == null) {
          _latestError = "Proxy scan cancelled";
          state = KoshianMeshProxyState.disconnected;
          logger.i(_latestError);
        }
        else {
          if (specificDevice != null) {
            _latestError = "Specific proxy device (${specificDevice.id}) could not be found";
          }
          else {
            _latestError = "A proxy device could not be found";
          }
          state = KoshianMeshProxyState.error;
          logger.w(_latestError);
        }
        return false;
      }
      _proxyScanListener = null;
      BleMeshManager().callbacks = _BleMeshManagerProxyCallbacks(nordicNrfMesh.meshManagerApi);
      _onMeshPduCreatedSubscription = nordicNrfMesh.meshManagerApi.onMeshPduCreated.listen((event) async {
        await BleMeshManager().sendPdu(event);
      });
      _onDataSentSubscription = Platform.isAndroid ? BleMeshManager().callbacks!.onDataSent.listen((event) async {
        await nordicNrfMesh.meshManagerApi.handleWriteCallbacks(event.mtu, event.pdu);
      }) : null;
      _onDataReceivedSubscription = BleMeshManager().callbacks!.onDataReceived.listen((event) async {
        await nordicNrfMesh.meshManagerApi.handleNotifications(event.mtu, event.pdu);
      });
      _onDeviceDisconnectedSubscription = BleMeshManager().callbacks!.onDeviceDisconnected.listen((event) async {
        _clearSubscriptions();
        await FlutterReactiveBle().deinitialize();
        state = KoshianMeshProxyState.disconnected;
        logger.i("Disconnected from proxy");
      });
      await BleMeshManager().connect(proxyDevice);
      logger.i("Connected to proxy ${BleMeshManager().device?.id}");
      state = KoshianMeshProxyState.connected;
      return true;
    }
    catch (e, s) {
      logger.e("Proxy connection error: $e\r\n$s");
      _latestError = e.toString();
      _proxyScanCompleter = null;
      _clearSubscriptions();
      await BleMeshManager().disconnect();
      state = KoshianMeshProxyState.error;
    }
    return false;
  }

  Future<void> disconnect() async {
    await _proxyScanListener?.cancel();
    _proxyScanListener = null;
    if (_proxyScanCompleter != null && !_proxyScanCompleter!.isCompleted) {
      _proxyScanCompleter?.complete(null);
    }
    _proxyScanCompleter = null;
    await BleMeshManager().disconnect();
    state = KoshianMeshProxyState.disconnected;
    logger.i("Proxy disconnect done");
  }
}

final koshianMeshProxyProvider = StateNotifierProvider<KoshianMeshProxyNotifier, KoshianMeshProxyState>((ref) {
  var inst = KoshianMeshProxyNotifier(ref);
  return inst;
});


// ------------------------------------------------------------------------------------
// - Koshian device list provider.

class KoshianNode {
  ProvisionedMeshNode node;
  String name;
  int unicastAddress;
  KoshianNode(this.node, this.name, this.unicastAddress);
}

class KoshianNodeListNotifier extends StateNotifier<List<KoshianNode>> {
  final Ref ref;

  KoshianNodeListNotifier(this.ref) : super([]) {
    ref.listen(meshNetworkProvider, (previous, next) async {
      List<KoshianNode> newMeshNodes = [];
      var nodes = await next?.nodes ?? [];
      for (var node in nodes) {
        var unicastAddress = await node.unicastAddress;
        if (unicastAddress != 1) { // not the provisioner node
          var name = await node.name;
          newMeshNodes.add(KoshianNode(node, name, unicastAddress));
        }
      }
      state = newMeshNodes;
    });
  }
}

final koshianNodeListProvider = StateNotifierProvider<KoshianNodeListNotifier, List<KoshianNode>>((ref) {
  var inst = KoshianNodeListNotifier(ref);
  return inst;
});
