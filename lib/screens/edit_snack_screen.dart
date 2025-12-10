// lib/screens/edit_snack_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:expiry_date/core/jan_master/jan_master_repository.dart';
import 'package:expiry_date/core/user/user_providers.dart';
import 'package:expiry_date/models/snack_item.dart';

class EditSnackScreen extends ConsumerStatefulWidget {
  const EditSnackScreen({
    super.key,
    required this.docId,
    required this.snack,
  });

  /// Firestore 上の snacks コレクションのドキュメントID。
  final String docId;

  /// 編集対象の商品情報。
  final SnackItem snack;

  @override
  ConsumerState<EditSnackScreen> createState() => _EditSnackScreenState();
}

class _EditSnackScreenState extends ConsumerState<EditSnackScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _priceController;

  late DateTime _selectedDate;
  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;

  late List<int> _yearOptions;
  static const int _yearRangeBefore = 5;
  static const int _yearRangeAfter = 10;

  bool _isSaving = false;

  List<int> _dayOptions = <int>[];

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.snack.name);
    _priceController = TextEditingController(
      text: widget.snack.price?.toString() ?? '',
    );

    _selectedDate = widget.snack.expiry;
    _selectedYear = _selectedDate.year;
    _selectedMonth = _selectedDate.month;
    _selectedDay = _selectedDate.day;

    final now = DateTime.now();
    final minYear = (now.year - _yearRangeBefore < _selectedYear)
        ? now.year - _yearRangeBefore
        : _selectedYear;
    final maxYear = (now.year + _yearRangeAfter > _selectedYear)
        ? now.year + _yearRangeAfter
        : _selectedYear;

    _yearOptions = [
      for (int y = minYear; y <= maxYear; y++) y,
    ];

    _rebuildDayOptions(adjustSelectedDay: true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _rebuildDayOptions({bool adjustSelectedDay = false}) {
    final lastDay = _lastDayOfMonth(_selectedYear, _selectedMonth);
    _dayOptions = [for (int d = 1; d <= lastDay; d++) d];

    if (adjustSelectedDay && _selectedDay > lastDay) {
      _selectedDay = lastDay;
    }
  }

  int _lastDayOfMonth(int year, int month) {
    final beginningNextMonth = (month == 12)
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
    final lastDayDate = beginningNextMonth.subtract(const Duration(days: 1));
    return lastDayDate.day;
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  Future<void> _pickDateWithCalendar() async {
    final initialDate = _selectedDate;
    final firstDate = DateTime(initialDate.year - _yearRangeBefore, 1, 1);
    final lastDate = DateTime(initialDate.year + _yearRangeAfter, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = picked;
      _selectedYear = picked.year;
      _selectedMonth = picked.month;
      _selectedDay = picked.day;

      if (!_yearOptions.contains(_selectedYear)) {
        final allYears = <int>[..._yearOptions, _selectedYear];
        allYears.sort();
        _yearOptions = allYears;
      }

      _rebuildDayOptions(adjustSelectedDay: true);
    });
  }

  Future<void> _onSave() async {
    if (_isSaving) {
      return;
    }

    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final shopId = ref.read(currentShopIdProvider);
    if (shopId.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('ショップ情報を取得できませんでした。再度ログインしてください。'),
        ),
      );
      return;
    }

    final name = _nameController.text.trim();
    final priceText = _priceController.text.trim();
    int? price;

    if (priceText.isNotEmpty) {
      final normalized = priceText.replaceAll(',', '');
      price = int.tryParse(normalized);
      if (price == null || price < 0) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('売価には0以上の数値を入力してください。')),
        );
        return;
      }
    }

    final expiry = DateTime(_selectedYear, _selectedMonth, _selectedDay);

    final user = FirebaseAuth.instance.currentUser;
    final db = FirebaseFirestore.instance;

    setState(() {
      _isSaving = true;
    });

    try {
      await db
          .collection('shops')
          .doc(shopId)
          .collection('snacks')
          .doc(widget.docId)
          .update(<String, Object?>{
        'name': name,
        'price': price,
        'expiry': Timestamp.fromDate(expiry),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUserId': user?.uid,
      });

      final jan = widget.snack.janCode;
      if (jan != null && jan.isNotEmpty) {
        final repo = ref.read(janMasterRepositoryProvider);
        await repo.upsertJan(
          janCode: jan,
          name: name,
          price: price,
          userId: user?.uid ?? 'anonymous',
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('商品の更新に失敗しました: $e'),
        ),
      );
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final janCode = widget.snack.janCode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('商品を編集'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (janCode != null && janCode.isNotEmpty) ...[
                  Text(
                    'JANコード',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    janCode,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '商品名',
                    hintText: '例）うまい棒 めんたい味',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '商品名を入力してください';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  '賞味期限',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('year-$_selectedYear'),
                        initialValue: _selectedYear,
                        decoration: const InputDecoration(
                          labelText: '年',
                        ),
                        items: _yearOptions
                            .map(
                              (y) => DropdownMenuItem<int>(
                            value: y,
                            child: Text('$y年'),
                          ),
                        )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _selectedYear = value;
                            _rebuildDayOptions(adjustSelectedDay: true);
                            _selectedDate = DateTime(
                              _selectedYear,
                              _selectedMonth,
                              _selectedDay,
                            );
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('month-$_selectedMonth'),
                        initialValue: _selectedMonth,
                        decoration: const InputDecoration(
                          labelText: '月',
                        ),
                        items: List<int>.generate(12, (index) => index + 1)
                            .map(
                              (m) => DropdownMenuItem<int>(
                            value: m,
                            child: Text('$m月'),
                          ),
                        )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _selectedMonth = value;
                            _rebuildDayOptions(adjustSelectedDay: true);
                            _selectedDate = DateTime(
                              _selectedYear,
                              _selectedMonth,
                              _selectedDay,
                            );
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('day-$_selectedDay'),
                        initialValue: _selectedDay,
                        decoration: const InputDecoration(
                          labelText: '日',
                        ),
                        items: _dayOptions
                            .map(
                              (d) => DropdownMenuItem<int>(
                            value: d,
                            child: Text('$d日'),
                          ),
                        )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _selectedDay = value;
                            _selectedDate = DateTime(
                              _selectedYear,
                              _selectedMonth,
                              _selectedDay,
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _pickDateWithCalendar,
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('カレンダーから選択'),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(
                    labelText: '売価（円）',
                    hintText: '例）30',
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return null;
                    }
                    final normalized = value.replaceAll(',', '').trim();
                    final parsed = int.tryParse(normalized);
                    if (parsed == null || parsed < 0) {
                      return '0以上の数値を入力してください';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () {
                          Navigator.of(context).pop();
                        },
                        child: const Text('キャンセル'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isSaving ? null : _onSave,
                        child: _isSaving
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
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
