import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:expiry_date/core/shop/shop_repository.dart';
import 'package:expiry_date/core/user/user_providers.dart';
import 'package:expiry_date/core/snacks/snack_repository.dart';
import 'package:expiry_date/models/snack_item.dart';
// ★追加: 共通ダイアログをインポート
import 'package:expiry_date/widgets/frequent_prices_dialog.dart';

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
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  final _formKey = GlobalKey<FormState>();

  bool _isSaving = false;

  // OCR関連
  final ImagePicker _picker = ImagePicker();
  bool _isRunningOcr = false;
  String? _ocrErrorMessage;

  // 賞味期限
  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.snack.name);
    _priceController = TextEditingController(
      text: widget.snack.price != null ? widget.snack.price.toString() : '',
    );
    _initExpiryDate(widget.snack.expiry);
  }

  void _initExpiryDate(DateTime date) {
    _selectedYear = date.year;
    _selectedMonth = date.month;
    _selectedDay = date.day;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  // ==========================================
  // 日付関連ヘルパー
  // ==========================================
  int _lastDayOfMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  int _daysInMonth(int year, int month) {
    return _lastDayOfMonth(year, month);
  }

  DateTime? _buildSelectedExpiry() {
    try {
      if (_selectedDay == -1) {
        final last = _lastDayOfMonth(_selectedYear, _selectedMonth);
        return DateTime(_selectedYear, _selectedMonth, last);
      }
      return DateTime(_selectedYear, _selectedMonth, _selectedDay);
    } catch (_) {
      return null;
    }
  }

  void _applyExpiryFromDate(DateTime date) {
    setState(() {
      _selectedYear = date.year;
      _selectedMonth = date.month;
      _selectedDay = date.day;
      _ocrErrorMessage = null;
    });
  }

  bool _isExpired(DateTime? date) {
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return date.isBefore(today);
  }

  // ==========================================
  // UI構築
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final bigTheme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(fontSizeFactor: 1.12),
    );
    final shopId = ref.watch(currentShopIdProvider);

    final expiryDate = _buildSelectedExpiry();
    final isExpired = _isExpired(expiryDate);
    final backgroundColor = isExpired ? Colors.red.shade50 : baseTheme.colorScheme.surface;

    return Theme(
      data: bigTheme,
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: backgroundColor,
            resizeToAvoidBottomInset: true,
            appBar: AppBar(
              title: const Text('商品を修正'),
              backgroundColor: isExpired ? Colors.red.shade100 : null,
            ),
            body: SafeArea(
              child: Column(
                children: [
                  if (isExpired)
                    Container(
                      width: double.infinity,
                      color: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: const Text(
                        '⚠️ 賞味期限が切れています',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: SingleChildScrollView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildJanSection(context),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _nameController,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                                decoration: const InputDecoration(labelText: '商品名', hintText: '例）うまい棒'),
                                textInputAction: TextInputAction.next,
                                validator: (v) => (v == null || v.trim().isEmpty) ? '商品名を入力してください' : null,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '賞味期限',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (_isRunningOcr)
                                    const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                  else
                                    IconButton(
                                      tooltip: 'カメラで読み取る（OCR）',
                                      onPressed: _isSaving ? null : _onTapCaptureExpiry,
                                      icon: const Icon(Icons.camera_alt_outlined),
                                    ),
                                ],
                              ),
                              if (_ocrErrorMessage != null) ...[
                                const SizedBox(height: 6),
                                Text(_ocrErrorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
                              ],
                              const SizedBox(height: 4),
                              _buildExpiryDropdowns(context),
                              const SizedBox(height: 24),
                              _buildPriceSection(context, shopId),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Container(
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.8)),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                                foregroundColor: Colors.grey,
                              ),
                              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                              child: const Text('キャンセル'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: isExpired ? Colors.red : Colors.redAccent,
                                minimumSize: const Size.fromHeight(54),
                              ),
                              onPressed: _isSaving ? null : () => _onSubmit(),
                              child: _isSaving
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('保存'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildJanSection(BuildContext context) {
    final janCode = widget.snack.janCode;
    final hasJan = janCode != null && janCode.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('JANコード', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            hasJan ? janCode : '（未登録）',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: hasJan ? null : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection(BuildContext context, String shopId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _priceController,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(labelText: '売価（円）', hintText: '例）30'),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            final p = int.tryParse(v.replaceAll(',', '').trim());
            if (p == null || p < 0) return '0以上の数値';
            return null;
          },
          onFieldSubmitted: (_) => _onSubmit(),
        ),
        const SizedBox(height: 8),

        if (shopId.isNotEmpty)
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('shops').doc(shopId).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final data = snapshot.data!.data();
              if (data == null) return const SizedBox.shrink();

              final List<dynamic> rawList = data['frequentPrices'] ?? [];
              final prices = rawList.cast<int>()..sort();

              return SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  alignment: WrapAlignment.start,
                  children: [
                    ...prices.map((price) {
                      return ActionChip(
                        label: Text('$price円'),
                        onPressed: () {
                          _priceController.text = price.toString();
                          FocusScope.of(context).unfocus();
                        },
                      );
                    }),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('追加'),
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      onPressed: () => _showFrequentPricesManageDialog(context, shopId),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildExpiryDropdowns(BuildContext context) {
    final now = DateTime.now();
    final years = <int>[for (int y = now.year - 1; y <= now.year + 10; y++) y];
    final months = List<int>.generate(12, (i) => i + 1);

    final maxDay = _daysInMonth(_selectedYear, _selectedMonth);
    final dayItems = <DropdownMenuItem<int>>[
      const DropdownMenuItem(value: -1, child: Text('末日')),
      ...List.generate(maxDay, (i) => i + 1).map((d) => DropdownMenuItem(value: d, child: Text('$d日'))),
    ];

    final validYear = years.contains(_selectedYear) ? _selectedYear : years.first;
    final validMonth = months.contains(_selectedMonth) ? _selectedMonth : 1;
    var validDay = _selectedDay;
    if (validDay != -1 && validDay > maxDay) validDay = maxDay;

    Widget buildDropdown<T>({
      required String label,
      required T value,
      required List<DropdownMenuItem<T>> items,
      required ValueChanged<T?>? onChanged,
    }) {
      return Expanded(
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        buildDropdown<int>(
          label: '年',
          value: validYear,
          items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y年'))).toList(),
          onChanged: _isSaving ? null : (v) => setState(() { if(v != null) _selectedYear = v; _ocrErrorMessage = null; }),
        ),
        const SizedBox(width: 8),
        buildDropdown<int>(
          label: '月',
          value: validMonth,
          items: months.map((m) => DropdownMenuItem(value: m, child: Text('$m月'))).toList(),
          onChanged: _isSaving ? null : (v) => setState(() { if(v != null) _selectedMonth = v; _ocrErrorMessage = null; }),
        ),
        const SizedBox(width: 8),
        buildDropdown<int>(
          label: '日',
          value: validDay,
          items: dayItems,
          onChanged: _isSaving ? null : (v) => setState(() { if(v != null) _selectedDay = v; _ocrErrorMessage = null; }),
        ),
      ],
    );
  }

  Future<void> _onSubmit() async {
    FocusScope.of(context).unfocus();
    if (_isSaving) return;
    if (_formKey.currentState?.validate() != true) return;

    final expiry = _buildSelectedExpiry();
    if (expiry == null) {
      setState(() => _ocrErrorMessage = '賞味期限を選択してください。');
      return;
    }

    final name = _nameController.text.trim();
    final price = int.tryParse(_priceController.text.replaceAll(',', '').trim());

    setState(() => _isSaving = true);

    try {
      final updatedItem = widget.snack.copyWith(
        name: name,
        expiry: expiry,
        price: price,
      );

      await ref.read(snackRepositoryProvider).updateSnack(updatedItem);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('商品を修正しました')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _ocrErrorMessage = '保存に失敗しました: $e';
      });
    }
  }

  Future<void> _showFrequentPricesManageDialog(BuildContext context, String shopId) async {
    FocusScope.of(context).unfocus();
    final doc = await FirebaseFirestore.instance.collection('shops').doc(shopId).get();
    final rawList = doc.data()?['frequentPrices'] as List<dynamic>? ?? [];
    final currentPrices = rawList.cast<int>()..sort();

    if (!context.mounted) return;

    await showDialog(
      context: context,
      // ★修正: 共通ウィジェットを使用
      builder: (ctx) => FrequentPricesDialog(
        initialPrices: currentPrices,
        onSave: (newPrices) async {
          final repo = ref.read(shopRepositoryProvider);
          await repo.updateFrequentPrices(shopId, newPrices);
        },
      ),
    );
  }

  Future<void> _onTapCaptureExpiry() async {
    setState(() {
      _isRunningOcr = true;
      _ocrErrorMessage = null;
    });

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image == null) {
        setState(() => _isRunningOcr = false);
        return;
      }

      final inputImage = InputImage.fromFilePath(image.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.japanese);

      try {
        final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
        final text = recognizedText.text;

        final date = _tryParseExpiryFromText(text);
        if (date != null) {
          _applyExpiryFromDate(date);
        } else {
          setState(() => _ocrErrorMessage = '日付を読み取れませんでした');
        }
      } finally {
        textRecognizer.close();
      }
    } catch (e) {
      setState(() => _ocrErrorMessage = '読み取りエラー: $e');
    } finally {
      if (mounted) setState(() => _isRunningOcr = false);
    }
  }

  DateTime? _tryParseExpiryFromText(String text) {
    final patterns = [
      RegExp(r'20(\d{2})[\./-](\d{1,2})[\./-](\d{1,2})'),
      RegExp(r'(\d{4})[\./-](\d{1,2})[\./-](\d{1,2})'),
      RegExp(r'(\d{2})[\./-](\d{1,2})[\./-](\d{1,2})'),
    ];

    final lines = text.split('\n');
    for (final line in lines) {
      for (final regex in patterns) {
        final match = regex.firstMatch(line);
        if (match != null) {
          try {
            int y = int.parse(match.group(1)!);
            int m = int.parse(match.group(2)!);
            int d = int.parse(match.group(3)!);
            if (y < 100) y += 2000;
            return DateTime(y, m, d);
          } catch (_) {
            continue;
          }
        }
      }
    }
    return null;
  }
}