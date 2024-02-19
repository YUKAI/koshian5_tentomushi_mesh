import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koshian5_tentomushi_mesh/bluetooth_provider.dart';
import 'package:koshian5_tentomushi_mesh/debug.dart';
import 'package:koshian5_tentomushi_mesh/router.dart';
import 'package:nordic_nrf_mesh/nordic_nrf_mesh.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  List<Map<String, dynamic>> meshNodes = [];

  Future<void> getNodesList(IMeshNetwork? meshNetwork) async {
    List<Map<String, dynamic>> newMeshNodes = [];
    var nodes = await meshNetwork?.nodes ?? [];
    logger.i("Mesh nodes: $nodes");
    for (var node in nodes) {
      Map<String, dynamic> info = {};
      info["name"] = await node.name;
      info["uuid"] = node.uuid;
      info["address"] = await node.unicastAddress;
      info["elements"] = await node.elements;
      newMeshNodes.add(info);
    }
    meshNodes = newMeshNodes;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    NetworkKey? meshNetworkKey = ref.watch(meshNetworkKeyProvider);
    IMeshNetwork? meshNetwork = ref.watch(meshNetworkProvider);
    ref.listen(meshNetworkProvider, (previous, next) async {
      if (next != null) {
        await getNodesList(next);
      }
    });
    bool onoff = false;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("テントウムシ"),
        actions: [
          IconButton(
            onPressed: () {
              ref.read(routerProvider).push('/addDevice');
            },
            icon: const Icon(Icons.add)
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const Text("Home"),
            Text("Network: ${meshNetwork?.id ?? "null"}"),
            Text("Network key: ${meshNetworkKey?.netKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join("") ?? "null"}"),
            OutlinedButton(
              onPressed: () async {
                await getNodesList(meshNetwork);
              },
              child: const Text("Get nodes")
            ),
            OutlinedButton(
              onPressed: () async {
                await ref.read(meshNetworkProvider.notifier).reset();
              },
              child: const Text("Reset network")
            ),
            ...meshNodes.map((e) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Node: ${e["name"]}"),
                          Text("${e["uuid"]}"),
                          Text("Address: ${e["address"]}"),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...e["elements"].map((l) => Text("${l.address} ${l.name}")),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Column(
                        children: [
                          OutlinedButton(
                            onPressed: () {
                              StreamSubscription<List<int>>? onMeshPduCreatedSubscription;
                              StreamSubscription<BleMeshManagerCallbacksDataSent>? onDataSentSubscription;
                              StreamSubscription<BleMeshManagerCallbacksDataReceived>? onDataReceivedSubscription;
                              Future.delayed(const Duration(), () async {
                                final proxyScanCompleter = Completer<DiscoveredDevice?>();
                                StreamSubscription<DiscoveredDevice>? proxyScanListener;
                                //
                                proxyScanListener = nordicNrfMesh.scanForProxy().listen((scannedDevice) {
                                  if (scannedDevice.serviceData.containsKey(meshProxyUuid)) {
                                    proxyScanCompleter.complete(scannedDevice);
                                  }
                                });
                                var proxyDevice = await proxyScanCompleter.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
                                if (proxyDevice == null) {
                                  throw "Proxy scan error";
                                }
                                logger.d("Found proxy device: $proxyDevice");
                                await proxyScanListener.cancel();
                                final setupCallbacks = BleMeshManagerSetupCallbacks(nordicNrfMesh.meshManagerApi);
                                BleMeshManager().callbacks = setupCallbacks;
                                onMeshPduCreatedSubscription = nordicNrfMesh.meshManagerApi.onMeshPduCreated.listen((event) async {
                                  logger.d("Mesh PDU created: send PDU");
                                  await BleMeshManager().sendPdu(event);
                                });
                                onDataSentSubscription = Platform.isAndroid ? BleMeshManager().callbacks!.onDataSent.listen((event) async {
                                  logger.d("Mesh data sent: handle write callbacks");
                                  await nordicNrfMesh.meshManagerApi.handleWriteCallbacks(event.mtu, event.pdu);
                                }) : null;
                                onDataReceivedSubscription = BleMeshManager().callbacks!.onDataReceived.listen((event) async {
                                  logger.d("Mesh data sent: handle notifications");
                                  await nordicNrfMesh.meshManagerApi.handleNotifications(event.mtu, event.pdu);
                                });
                                await BleMeshManager().connect(proxyDevice);
                                logger.d("Connected to proxy device");
                                await Future.delayed(const Duration(seconds: 1));
                                onoff = !onoff;
                                var res2 = await nordicNrfMesh.meshManagerApi.sendGenericOnOffSet(
                                    e["address"]+2,
                                    onoff,
                                    await nordicNrfMesh.meshManagerApi.getSequenceNumberForAddress(e["address"])
                                );
                                logger.i("Control result: $res2");
                                await onMeshPduCreatedSubscription?.cancel();
                                await onDataSentSubscription?.cancel();
                                await onDataReceivedSubscription?.cancel();
                                await BleMeshManager().disconnect();
                              }).timeout(const Duration(seconds: 20), onTimeout: () async {
                                logger.i("Control timeout, clean up");
                                await onMeshPduCreatedSubscription?.cancel();
                                await onDataSentSubscription?.cancel();
                                await onDataReceivedSubscription?.cancel();
                                await BleMeshManager().disconnect();
                              }).onError((error, stackTrace) async {
                                logger.i("Control error ($error), clean up\r\n$stackTrace");
                                await onMeshPduCreatedSubscription?.cancel();
                                await onDataSentSubscription?.cancel();
                                await onDataReceivedSubscription?.cancel();
                                await BleMeshManager().disconnect();
                              });
                            },
                            child: const Text("Control"),
                          ),
                          OutlinedButton(
                              onPressed: () {
                                StreamSubscription<List<int>>? onMeshPduCreatedSubscription;
                                StreamSubscription<BleMeshManagerCallbacksDataSent>? onDataSentSubscription;
                                StreamSubscription<BleMeshManagerCallbacksDataReceived>? onDataReceivedSubscription;
                                Future.delayed(const Duration(), () async {
                                  final proxyScanCompleter = Completer<DiscoveredDevice?>();
                                  StreamSubscription<DiscoveredDevice>? proxyScanListener;
                                  //
                                  proxyScanListener = nordicNrfMesh.scanForProxy().listen((scannedDevice) {
                                    if (scannedDevice.serviceData.containsKey(meshProxyUuid)) {
                                      proxyScanCompleter.complete(scannedDevice);
                                    }
                                  });
                                  var proxyDevice = await proxyScanCompleter.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
                                  if (proxyDevice == null) {
                                    throw "Proxy scan error";
                                  }
                                  logger.d("Found proxy device: $proxyDevice");
                                  await proxyScanListener.cancel();
                                  final setupCallbacks = BleMeshManagerSetupCallbacks(nordicNrfMesh.meshManagerApi);
                                  BleMeshManager().callbacks = setupCallbacks;
                                  onMeshPduCreatedSubscription = nordicNrfMesh.meshManagerApi.onMeshPduCreated.listen((event) async {
                                    logger.d("Mesh PDU created: send PDU");
                                    await BleMeshManager().sendPdu(event);
                                  });
                                  onDataSentSubscription = Platform.isAndroid ? BleMeshManager().callbacks!.onDataSent.listen((event) async {
                                    logger.d("Mesh data sent: handle write callbacks");
                                    await nordicNrfMesh.meshManagerApi.handleWriteCallbacks(event.mtu, event.pdu);
                                  }) : null;
                                  onDataReceivedSubscription = BleMeshManager().callbacks!.onDataReceived.listen((event) async {
                                    logger.d("Mesh data sent: handle notifications");
                                    await nordicNrfMesh.meshManagerApi.handleNotifications(event.mtu, event.pdu);
                                  });
                                  await BleMeshManager().connect(proxyDevice);
                                  logger.d("Connected to proxy device");
                                  await Future.delayed(const Duration(seconds: 1));
                                  var res = await nordicNrfMesh.meshManagerApi.sendConfigModelAppBind(
                                      e["address"],
                                      e["address"]+2,
                                      0x1000
                                  );
                                  logger.i("Configure result: $res");
                                  await onMeshPduCreatedSubscription?.cancel();
                                  await onDataSentSubscription?.cancel();
                                  await onDataReceivedSubscription?.cancel();
                                  await BleMeshManager().disconnect();
                                }).timeout(const Duration(seconds: 20), onTimeout: () async {
                                  logger.i("Configure timeout, clean up");
                                  await onMeshPduCreatedSubscription?.cancel();
                                  await onDataSentSubscription?.cancel();
                                  await onDataReceivedSubscription?.cancel();
                                  await BleMeshManager().disconnect();
                                }).onError((error, stackTrace) async {
                                  logger.i("Configure error ($error), clean up\r\n$stackTrace");
                                  await onMeshPduCreatedSubscription?.cancel();
                                  await onDataSentSubscription?.cancel();
                                  await onDataReceivedSubscription?.cancel();
                                  await BleMeshManager().disconnect();
                                });
                              },
                              child: const Text("Configure"),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              meshNetwork?.deleteNode(e["uuid"]);
                            },
                            child: const Icon(Icons.delete),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 1, thickness: 0, indent: 0, endIndent: 0),
                ]
            )),
          ],
        )
      ),
    );
  }
}


class BleMeshManagerSetupCallbacks extends BleMeshManagerCallbacks {
  final MeshManagerApi meshManagerApi;

  /// {@macro prov_ble_manager}
  BleMeshManagerSetupCallbacks(this.meshManagerApi);

  @override
  Future<void> sendMtuToMeshManagerApi(int mtu) => meshManagerApi.setMtu(mtu);
}
