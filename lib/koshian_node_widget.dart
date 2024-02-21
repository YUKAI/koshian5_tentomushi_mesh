import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bluetooth_provider.dart';


class KoshianNodeWidget extends ConsumerStatefulWidget
{
  final KoshianNode node;
  const KoshianNodeWidget({
    super.key,
    required this.node,
  });

  @override
  ConsumerState<KoshianNodeWidget> createState() => _KoshianNodeWidgetState();
}

class _KoshianNodeWidgetState<T> extends ConsumerState<KoshianNodeWidget> {
  double motorControl = 0.0;
  bool redControl = false;
  bool greenControl = false;
  bool blueControl = false;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Padding(padding: const EdgeInsets.all(8.0), child: InkWell(
              onDoubleTap: () async {
                showDialog(context: context, builder: (ctx) {
                  return AlertDialog(
                    title: const Text("このノードを削除しますか？"),
                    actions: [
                      TextButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop(null);
                          await ref.read(meshNetworkProvider)?.deleteNode(widget.node.node.uuid);
                          await ref.read(meshNetworkProvider.notifier).reload();
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
                  Text(widget.node.name),
                  Text(widget.node.node.uuid),
                ],
              ),
            )),
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
                        nordicNrfMesh.meshManagerApi.sendGenericOnOffSet(
                            widget.node.unicastAddress+8,
                            redControl,
                            await nordicNrfMesh.meshManagerApi.getSequenceNumberForAddress(widget.node.unicastAddress)
                        );
                      },
                    ),
                    ColorToggleButton(
                      color: Colors.green,
                      value: greenControl,
                      onPressed: () async {
                        setState(() {
                          greenControl = !greenControl;
                        });
                        await nordicNrfMesh.meshManagerApi.sendGenericOnOffSet(
                            widget.node.unicastAddress+2,
                            greenControl,
                            await nordicNrfMesh.meshManagerApi.getSequenceNumberForAddress(widget.node.unicastAddress)
                        );
                      },
                    ),
                    ColorToggleButton(
                      color: Colors.blue,
                      value: blueControl,
                      onPressed: () async {
                        setState(() {
                          blueControl = !blueControl;
                        });
                        await nordicNrfMesh.meshManagerApi.sendGenericOnOffSet(
                            widget.node.unicastAddress+7,
                            blueControl,
                            await nordicNrfMesh.meshManagerApi.getSequenceNumberForAddress(widget.node.unicastAddress)
                        );
                      },
                    ),
                  ],
                ),
                Slider(
                  value: motorControl,
                  onChanged: (val) {
                    setState(() {
                      motorControl = val;
                    });
                  },
                  onChangeEnd: (val) async {
                    await nordicNrfMesh.meshManagerApi.sendGenericLevelSet(
                      widget.node.unicastAddress+1,
                      (val*32767).toInt(),
                    );
                  },
                ),
              ]
            ),
          ],
        ),
      ],
    );
  }
}


class ColorToggleButton extends StatefulWidget
{
  final Color color;
  final bool value;
  final VoidCallback onPressed;
  const ColorToggleButton({
    super.key,
    required this.color,
    required this.value,
    required this.onPressed,
  });

  @override
  State<StatefulWidget> createState() => _ColorToggleButtonState();
}

class _ColorToggleButtonState<T> extends State<ColorToggleButton> {

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: ButtonStyle(
        shape: MaterialStateProperty.all<CircleBorder>(const CircleBorder()),
        backgroundColor: MaterialStateProperty.all<Color>(widget.value?widget.color:Colors.transparent),
        side: MaterialStateProperty.all<BorderSide>(
          BorderSide(
            color: widget.color,
            width: 3,
          )
        )
      ),
      onPressed: () {
        widget.onPressed();
      },
      child: const Text("")
    );
  }
}