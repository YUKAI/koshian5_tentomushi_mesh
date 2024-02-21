import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koshian5_tentomushi_mesh/bluetooth_provider.dart';
import 'package:koshian5_tentomushi_mesh/debug.dart';
import 'package:koshian5_tentomushi_mesh/koshian_node_widget.dart';
import 'package:koshian5_tentomushi_mesh/router.dart';
import 'package:nordic_nrf_mesh/nordic_nrf_mesh.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  List<KoshianNode> meshNodes = [];
  Map<int, List<dynamic>> nodeControlStates = {};

  @override
  Widget build(BuildContext context) {
    NetworkKey? meshNetworkKey = ref.watch(meshNetworkKeyProvider);
    IMeshNetwork? meshNetwork = ref.watch(meshNetworkProvider);
    var proxyConnectionState = ref.watch(koshianMeshProxyProvider);
    ref.listen(koshianNodeListProvider, (prev, next) {
      for (var n in next) {
        if (!nodeControlStates.containsKey(n.unicastAddress)) {
          nodeControlStates[n.unicastAddress] = [0.0,false,false,false];
        }
      }
      meshNodes = next;
      setState(() {});
    });
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
            Text("Network: ${meshNetwork?.id ?? "None"}"),
            Text("Network key: ${meshNetworkKey?.netKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join("") ?? "None"}"),
            OutlinedButton(
              onPressed: () async {
                await ref.read(meshNetworkProvider.notifier).reset();
              },
              child: const Text("Reset network")
            ),
            ...meshNodes.map((n) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KoshianNodeWidget(node: n),
                  Row(
                    children: [
                      const SizedBox(width: 6),
                      Column(
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              await meshNetwork?.deleteNode(n.node.uuid);
                              await ref.read(meshNetworkProvider.notifier).reload();
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
