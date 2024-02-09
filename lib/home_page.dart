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
                      OutlinedButton(
                        onPressed: () {
                          meshNetwork?.deleteNode(e["uuid"]);
                        },
                        child: const Icon(Icons.delete),
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
