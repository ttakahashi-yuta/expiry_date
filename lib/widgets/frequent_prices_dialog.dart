import 'package:flutter/material.dart';

class FrequentPricesDialog extends StatefulWidget {
  const FrequentPricesDialog({
    super.key,
    required this.initialPrices,
    required this.onSave,
  });

  final List<int> initialPrices;
  final ValueChanged<List<int>> onSave;

  @override
  State<FrequentPricesDialog> createState() => _FrequentPricesDialogState();
}

class _FrequentPricesDialogState extends State<FrequentPricesDialog> {
  late List<int> _prices;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prices = List.of(widget.initialPrices);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addPrice() {
    final val = int.tryParse(_controller.text);
    if (val != null && !_prices.contains(val)) {
      setState(() {
        _prices.add(val);
        _prices.sort();
        _controller.clear();
      });
    }
  }

  void _removePrice(int val) {
    setState(() {
      _prices.remove(val);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('よく使う売価の設定'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. 入力フォーム（固定表示）
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '追加する価格', hintText: '10'),
                  onSubmitted: (_) => _addPrice(),
                ),
              ),
              IconButton(icon: const Icon(Icons.add_circle), onPressed: _addPrice),
            ],
          ),
          const SizedBox(height: 16),

          // 2. チップ一覧（ここだけスクロール可能にする）
          Flexible(
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.maxFinite,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _prices.map((p) => Chip(
                    label: Text('$p円'),
                    onDeleted: () => _removePrice(p),
                  )).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_prices);
            Navigator.of(context).pop();
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}