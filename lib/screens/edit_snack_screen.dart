import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:expiry_date/core/jan_master/jan_master_repository.dart';
import 'package:expiry_date/core/user/user_providers.dart';
import 'package:expiry_date/core/snacks/snack_repository.dart';
import 'package:expiry_date/models/snack_item.dart';

class EditSnackScreen extends ConsumerStatefulWidget {
  const EditSnackScreen({
    super.key,
    required this.docId,
    required this.snack,
  });

  final String docId;
  final SnackItem snack;

  @override
  ConsumerState<EditSnackScreen> createState() => _EditSnackScreenState();
}

class _EditSnackScreenState extends ConsumerState<EditSnackScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _priceController;

  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;

  late List<int> _yearOptions;
  static const int _yearRangeBefore = 5;
  static const int _yearRangeAfter = 10;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.snack.name);
    _priceController = TextEditingController(
      text: widget.snack.price?.toString() ?? '',
    );

    final expiry = widget.snack.expiry;
    _selectedYear = expiry.year;
    _selectedMonth = expiry.month;
    _selectedDay = expiry.day;

    final now = DateTime.now();
    final minYear = (now.year - _yearRangeBefore < _selectedYear)
        ? now.year - _yearRangeBefore
        : _selectedYear;
    final maxYear = (now.year + _yearRangeAfter > _selectedYear)
        ? now.year + _yearRangeAfter
        : _selectedYear;

    _yearOptions = [for (int y = minYear; y <= maxYear; y++) y];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  // 月末日の計算
  int _lastDayOfMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  Future<void> _pickDateWithCalendar() async {
    final initialDate = DateTime(_selectedYear, _selectedMonth, _selectedDay);
    final firstDate = DateTime(initialDate.year - _yearRangeBefore, 1, 1);
    final lastDate = DateTime(initialDate.year + _yearRangeAfter, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked != null) {
      setState(() {
        _selectedYear = picked.year;
        _selectedMonth = picked.month;
        _selectedDay = picked.day;

        if (!_yearOptions.contains(_selectedYear)) {
          _yearOptions = [..._yearOptions, _selectedYear]..sort();
        }
      });
    }
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    if (_formKey.currentState?.validate() != true) return;

    final shopId = ref.read(currentShopIdProvider);
    if (shopId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('エラー: ショップ情報が取得できませんでした。')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final priceText = _priceController.text.replaceAll(',', '').trim();
      final price = priceText.isNotEmpty ? int.parse(priceText) : null;
      final expiry = DateTime(_selectedYear, _selectedMonth, _selectedDay);

      // ★リポジトリを使って更新（updatedAtなどが自動更新される）
      // copyWith で既存のIDやJANコードを引き継ぎつつ、新しい値をセット
      final updatedSnack = widget.snack.copyWith(
        name: name,
        price: price,
        expiry: expiry,
      );

      await ref.read(snackRepositoryProvider).updateSnack(updatedSnack);

      // JANマスタの更新（商品名や価格が変わった可能性があるため）
      final jan = widget.snack.janCode;
      if (jan != null && jan.isNotEmpty) {
        final user = ref.read(appUserStreamProvider).value;
        await ref.read(janMasterRepositoryProvider).upsertJan(
          janCode: jan,
          name: name,
          price: price,
          userId: user?.uid ?? 'anonymous',
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新に失敗しました: $e')),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final janCode = widget.snack.janCode;

    // 日付選択肢の計算
    final maxDay = _lastDayOfMonth(_selectedYear, _selectedMonth);
    // 選択中の日が月末を超えていたら補正する（表示上のみ）
    final displayDay = (_selectedDay > maxDay) ? maxDay : _selectedDay;
    final dayItems = [
      for (int d = 1; d <= maxDay; d++) DropdownMenuItem(value: d, child: Text('$d日'))
    ];

    // ドロップダウン構築用ヘルパー
    Widget buildDropdown<T>({
      required String label,
      required T value,
      required List<DropdownMenuItem<T>> items,
      required ValueChanged<T?> onChanged,
    }) {
      return Expanded(
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              items: items,
              onChanged: _isSaving ? null : onChanged,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('商品を編集')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (janCode != null && janCode.isNotEmpty) ...[
                  Text('JANコード', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  SelectableText(janCode, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: '商品名', hintText: '例）うまい棒'),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty) ? '商品名を入力してください' : null,
                ),
                const SizedBox(height: 16),
                Text('賞味期限', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    buildDropdown<int>(
                      label: '年',
                      value: _selectedYear,
                      items: _yearOptions.map((y) => DropdownMenuItem(value: y, child: Text('$y年'))).toList(),
                      onChanged: (v) => setState(() => _selectedYear = v!),
                    ),
                    const SizedBox(width: 8),
                    buildDropdown<int>(
                      label: '月',
                      value: _selectedMonth,
                      items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(value: m, child: Text('$m月'))).toList(),
                      onChanged: (v) => setState(() => _selectedMonth = v!),
                    ),
                    const SizedBox(width: 8),
                    buildDropdown<int>(
                      label: '日',
                      value: displayDay,
                      items: dayItems,
                      onChanged: (v) => setState(() => _selectedDay = v!),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isSaving ? null : _pickDateWithCalendar,
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('カレンダーから選択'),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: '売価（円）', hintText: '例）30'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = int.tryParse(v.replaceAll(',', '').trim());
                    if (n == null || n < 0) return '0以上の数値を入力してください';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                        child: const Text('キャンセル'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isSaving ? null : _onSave,
                        child: _isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}