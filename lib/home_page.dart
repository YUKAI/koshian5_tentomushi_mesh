import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koshian5_tentomushi_mesh/bluetooth_provider.dart';
import 'package:koshian5_tentomushi_mesh/koshian_node_widget.dart';
import 'package:koshian5_tentomushi_mesh/router.dart';
import 'package:nordic_nrf_mesh/nordic_nrf_mesh.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  double motorControl = -32768;
  bool redControl = false;
  bool greenControl = false;
  bool blueControl = false;
  KoshianMeshProxyState proxyConnectionState = KoshianMeshProxyState.disconnected;
  bool allowProxyAutoConnect = false;

  @override
  Widget build(BuildContext context) {
    NetworkKey? meshNetworkKey = ref.watch(meshNetworkKeyProvider);
    IMeshNetwork? meshNetwork = ref.watch(meshNetworkProvider);
    ref.listen(koshianMeshProxyProvider, (_, proxyState) {
      setState(() {
        proxyConnectionState = proxyState;
      });
      if (proxyState == KoshianMeshProxyState.disconnected || proxyState == KoshianMeshProxyState.error) {
        if (allowProxyAutoConnect) {
          ref.read(koshianMeshProxyProvider.notifier).connect();
        }
      }
    });
    var meshNodes = ref.watch(koshianNodeListProvider);
    var meshGroups = ref.watch(meshGroupsProvider);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("テントウムシ"),
        actions: [
          FilledButton(
            onPressed: () {
              if (proxyConnectionState == KoshianMeshProxyState.connected || proxyConnectionState == KoshianMeshProxyState.connecting) {
                allowProxyAutoConnect = false;
                ref.read(koshianMeshProxyProvider.notifier).disconnect();
              }
              else {
                allowProxyAutoConnect = true;
                ref.read(koshianMeshProxyProvider.notifier).connect();
              }
            },
            child: Text(
                proxyConnectionState==KoshianMeshProxyState.connected?"Proxy接続済み":
                proxyConnectionState==KoshianMeshProxyState.connecting?"Proxy接続中":
                proxyConnectionState==KoshianMeshProxyState.scanning?"Proxyスキャン中":
                "Proxy未接続"
            ),
          ),
          const SizedBox(width: 8,),
          OutlinedButton(
            onPressed: () {
              ref.read(routerProvider).push('/addDevice');
            },
            child: const Text("追加")
          ),
          const SizedBox(width: 8,),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 10,),
            Row(
              children: [
                Expanded(child: Padding(padding: const EdgeInsets.all(8.0), child: InkWell(
                  splashFactory: NoSplash.splashFactory,
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
                ))),
                Column(
                    children: [
                      Row(
                        children: [
                          ColorToggleButton(
                            color: Colors.red,
                            value: redControl,
                            onPressed: () async {
                              setState(() {
                                redControl = !redControl;
                              });
                              if (meshGroups.containsKey("pio7")) {
                                await nordicNrfMesh.meshManagerApi.sendGenericOnOffSet(
                                  meshGroups["pio7"]!.address,
                                    redControl
                                );
                              }
                            },
                          ),
                          ColorToggleButton(
                            color: Colors.green,
                            value: greenControl,
                            onPressed: () async {
                              setState(() {
                                greenControl = !greenControl;
                              });
                              if (meshGroups.containsKey("pio1")) {
                                await nordicNrfMesh.meshManagerApi.sendGenericOnOffSet(
                                  meshGroups["pio1"]!.address,
                                    greenControl
                                );
                              }
                            },
                          ),
                          ColorToggleButton(
                            color: Colors.blue,
                            value: blueControl,
                            onPressed: () async {
                              setState(() {
                                blueControl = !blueControl;
                              });
                              if (meshGroups.containsKey("pio6")) {
                                await nordicNrfMesh.meshManagerApi.sendGenericOnOffSet(
                                  meshGroups["pio6"]!.address,
                                  blueControl
                                );
                              }
                            },
                          ),
                        ]
                      ),
                      Slider(
                        value: motorControl,
                        min: -32768,
                        max: 32767,
                        onChanged: (val) {
                          setState(() {
                            motorControl = val;
                          });
                        },
                        onChangeEnd: (val) async {
                          if (meshGroups.containsKey("pio0")) {
                            await nordicNrfMesh.meshManagerApi.sendGenericLevelSet(
                              meshGroups["pio0"]!.address,
                              val.toInt(),
                            );
                          }
                        },
                      ),
                    ]
                ),
                const SizedBox(width: 80,),
              ],
            ),
            const Divider(height: 4, thickness: 3, indent: 0, endIndent: 0),
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
