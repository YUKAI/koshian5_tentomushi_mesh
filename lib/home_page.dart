import 'dart:async';

import 'package:flutter/material.dart';
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
  Map<int, List<double>> nodeSliderStates = {};

  @override
  void initState() {
    super.initState();
    // Future(() async {
    //   var res = await ref.read(koshianMeshProxyProvider.notifier).connect();
    //   logger.i("Connected to proxy: $res");
    // });
  }

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
      if (!nodeSliderStates.containsKey(info["address"])) {
        nodeSliderStates[info["address"]] = [0,0,0,0];
      }
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
    var proxyConnectionState = ref.watch(koshianMeshProxyProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("テントウムシ"),
        actions: [
          OutlinedButton(
            onPressed: () {
              if (proxyConnectionState == KoshianMeshProxyState.connected) {
                ref.read(koshianMeshProxyProvider.notifier).disconnect();
              }
              else {
                ref.read(koshianMeshProxyProvider.notifier).connect();
              }
            },
            child: Text(
                proxyConnectionState==KoshianMeshProxyState.connected?"接続済み":
                proxyConnectionState==KoshianMeshProxyState.connecting?"接続中":
                "接続"
            ),
          ),
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
                          Slider(
                            value: nodeSliderStates[e["address"]]![0],
                            onChanged: (val) {
                              setState(() {
                                nodeSliderStates[e["address"]]![0] = val;
                              });
                            },
                            onChangeEnd: (val) async {
                              if (e["address"] == 1) {
                                return;
                              }
                              await nordicNrfMesh.meshManagerApi.sendGenericLevelSet(
                                e["address"]+1,
                                (val*32767).toInt(),
                              );
                            },
                          ),
                          Slider(
                            value: nodeSliderStates[e["address"]]![1],
                            onChanged: (val) {
                              setState(() {
                                nodeSliderStates[e["address"]]![1] = val;
                              });
                            },
                            onChangeEnd: (val) async {
                              if (e["address"] == 1) {
                                return;
                              }
                              await nordicNrfMesh.meshManagerApi.sendGenericLevelSet(
                                e["address"]+2,
                                (val*32767).toInt(),
                              );
                            },
                          ),
                          Slider(
                            value: nodeSliderStates[e["address"]]![2],
                            onChanged: (val) {
                              setState(() {
                                nodeSliderStates[e["address"]]![2] = val;
                              });
                            },
                            onChangeEnd: (val) async {
                              if (e["address"] == 1) {
                                return;
                              }
                              await nordicNrfMesh.meshManagerApi.sendGenericLevelSet(
                                e["address"]+7,
                                (val*32767).toInt(),
                              );
                            },
                          ),
                          Slider(
                            value: nodeSliderStates[e["address"]]![3],
                            onChanged: (val) {
                              setState(() {
                                nodeSliderStates[e["address"]]![3] = val;
                              });
                            },
                            onChangeEnd: (val) async {
                              if (e["address"] == 1) {
                                return;
                              }
                              await nordicNrfMesh.meshManagerApi.sendGenericLevelSet(
                                e["address"]+8,
                                (val*32767).toInt(),
                              );
                            },
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
