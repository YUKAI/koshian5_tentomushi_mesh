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
  double motorControl = 0.0;
  bool ledControl = false;

  @override
  Widget build(BuildContext context) {
    NetworkKey? meshNetworkKey = ref.watch(meshNetworkKeyProvider);
    IMeshNetwork? meshNetwork = ref.watch(meshNetworkProvider);
    var proxyConnectionState = ref.watch(koshianMeshProxyProvider);
    var meshNodes = ref.watch(koshianNodeListProvider);
    var meshGroups = ref.watch(meshGroupsProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("テントウムシ"),
        actions: [
          OutlinedButton(
            onPressed: () {
              if (proxyConnectionState == KoshianMeshProxyState.connected || proxyConnectionState == KoshianMeshProxyState.connecting) {
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
            Row(
              children: [
                Padding(padding: const EdgeInsets.all(8.0), child: InkWell(
                  onDoubleTap: () async {
                    showDialog(context: context, builder: (ctx) {
                      return AlertDialog(
                        title: const Text("ネットワークをリセットしますか？"),
                        content: const Text("追加済みのノードはすべて消されます。"),
                        actions: [
                          TextButton(
                              onPressed: () async {
                                Navigator.of(ctx).pop(null);
                                await ref.read(meshNetworkProvider.notifier).reset();
                              },
                              child: const Text("はい")
                          ),
                          TextButton(
                              onPressed: () {
                                Navigator.of(context).pop(null);
                              },
                              child: const Text("キャンセル")
                          ),
                        ],
                      );
                    });
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("ネットワークUUID: ${meshNetwork?.id ?? "無"}"),
                      Text("ネットワークキー: ${meshNetworkKey?.netKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join("") ?? "無"}"),
                    ],
                  ),
                )),
                Column(
                    children: [
                      ColorToggleButton(
                        color: Colors.black,
                        value: ledControl,
                        onPressed: () async {
                          setState(() {
                            ledControl = !ledControl;
                          });
                          nordicNrfMesh.meshManagerApi.sendGenericOnOffSet(
                              0xffff,
                              ledControl
                          );
                        },
                      ),
                      Slider(
                        value: motorControl,
                        onChanged: (val) {
                          setState(() {
                            motorControl = val;
                          });
                        },
                        onChangeEnd: (val) async {
                          if (meshGroups.containsKey("pio0")) {
                            await nordicNrfMesh.meshManagerApi.sendGenericLevelSet(
                              meshGroups["pio0"]!.address,
                              (val * 32767).toInt(),
                            );
                          }
                        },
                      ),
                    ]
                ),
              ],
            ),
            OutlinedButton(
              onPressed: () async {
                logger.i("Groups: $meshGroups");
              },
              child: const Text("Groups")
            ),
            const Divider(height: 1, thickness: 0, indent: 0, endIndent: 0),
            const Divider(height: 1, thickness: 0, indent: 0, endIndent: 0),
            ...meshNodes.map((n) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KoshianNodeWidget(node: n),
                  const Divider(height: 1, thickness: 0, indent: 0, endIndent: 0),
                ]
            )),
          ],
        )
      ),
    );
  }
}
