import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:expiry_date/core/jan_master/jan_master_repository.dart';
import 'package:expiry_date/core/shop/shop_repository.dart';
import 'package:expiry_date/core/settings/app_settings.dart';
import 'package:expiry_date/core/user/user_providers.dart';
import 'package:expiry_date/core/snacks/snack_repository.dart';
import '../models/snack_item.dart';

class AddSnackFlowScreen extends ConsumerStatefulWidget {
  const AddSnackFlowScreen({super.key});

  @override
  ConsumerState<AddSnackFlowScreen> createState() => _AddSnackFlowScreenState();
}

class _AddSnackFlowScreenState extends ConsumerState<AddSnackFlowScreen> {
  late MobileScannerController _scannerController;

  // 入力状態
  String? _janCode;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSaving = false;

  // OCR関連
  final ImagePicker _picker = ImagePicker();
  bool _isRunningOcr = false;
  String? _ocrErrorMessage;

  // JANマスタ
  bool _isLoadingJanMaster = false;
  String? _janMasterErrorMessage;
  String? _masterName;
  int? _masterPrice;

  // 賞味期限
  int? _selectedYear;
  int? _selectedMonth;
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    _setExpiryToDefaultValues();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _setExpiryToDefaultValues() {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    _selectedYear = nextMonth.year;
    _selectedMonth = nextMonth.month;
    _selectedDay = -1; // 末日
  }

  int _lastDayOfMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  int _daysInMonth(int year, int month) {
    return _lastDayOfMonth(year, month);
  }

  DateTime? _buildSelectedExpiry() {
    if (_selectedYear == null || _selectedMonth == null || _selectedDay == null) {
      return null;
    }
    final year = _selectedYear!;
    final month = _selectedMonth!;
    final day = _selectedDay!;

    try {
      if (day == -1) {
        final last = _lastDayOfMonth(year, month);
        return DateTime(year, month, last);
      }
      return DateTime(year, month, day);
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

  void _resetFormForNext() {
    setState(() {
      _janCode = null;
      _nameController.text = '';
      _priceController.text = '';
      _ocrErrorMessage = null;
      _isLoadingJanMaster = false;
      _janMasterErrorMessage = null;
      _masterName = null;
      _masterPrice = null;
      _setExpiryToDefaultValues();
    });
  }

  /// 賞味期限切れ判定（今日より前なら期限切れ）
  bool _isExpired(DateTime? date) {
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return date.isBefore(today);
  }

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
              title: const Text('商品を追加'),
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
                              _buildJanSection(context, shopId),
                              const SizedBox(height: 16),

                              // 1. 商品名
                              TextFormField(
                                controller: _nameController,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                                decoration: const InputDecoration(labelText: '商品名', hintText: '例）うまい棒'),
                                textInputAction: TextInputAction.next,
                                validator: (v) => (v == null || v.trim().isEmpty) ? '商品名を入力してください' : null,
                              ),
                              const SizedBox(height: 16),

                              // 2. 賞味期限 (売価より先に移動)
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

                              // 3. 売価 (最後に配置)
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildKeepAddingCheckbox(context),
                          const SizedBox(height: 10),
                          Row(
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
                                      : const Text('登録'),
                                ),
                              ),
                            ],
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

  Widget _buildKeepAddingCheckbox(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final isKeepAdding = settings.isKeepAddingEnabled;

    return Row(
      children: [
        const Expanded(child: SizedBox.shrink()),
        const Text('連続登録'),
        const SizedBox(width: 8),
        Checkbox(
          value: isKeepAdding,
          onChanged: _isSaving
              ? null
              : (v) {
            ref.read(appSettingsProvider.notifier).setKeepAddingEnabled(v ?? false);
          },
        ),
      ],
    );
  }

  Widget _buildJanSection(BuildContext context, String shopId) {
    final hasJan = _janCode != null && _janCode!.trim().isNotEmpty;
    final canScan = !_isSaving && !_isRunningOcr && shopId.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('JANコード', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    SelectableText(hasJan ? _janCode! : '未入力', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: canScan ? () => _openBarcodeScannerModal(context) : null,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(_isLoadingJanMaster ? '取得中…' : 'スキャン'),
                ),
              ),
            ],
          ),
          if (shopId.isEmpty) ...[
            const SizedBox(height: 10),
            Text('店舗が未選択のためスキャンできません。', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],
          if (_janMasterErrorMessage != null) ...[
            const SizedBox(height: 10),
            Text(_janMasterErrorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  // 売価入力セクション（チップをWrapで折り返し表示）
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

        // よく使う売価チップ群
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
                    // 価格チップ
                    ...prices.map((price) {
                      return ActionChip(
                        label: Text('$price円'),
                        onPressed: () {
                          _priceController.text = price.toString();
                          FocusScope.of(context).unfocus();
                        },
                      );
                    }),

                    // 「＋」追加ボタン
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('追加'),
                      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
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
    final years = <int>[for (int y = now.year; y <= now.year + 5; y++) y];
    final months = List<int>.generate(12, (i) => i + 1);

    final baseYear = _selectedYear ?? now.year;
    final baseMonth = _selectedMonth ?? 1;
    final maxDay = _daysInMonth(baseYear, baseMonth);

    final dayItems = <DropdownMenuItem<int>>[
      const DropdownMenuItem(value: -1, child: Text('末日')),
      ...List.generate(maxDay, (i) => i + 1).map((d) => DropdownMenuItem(value: d, child: Text('$d日'))),
    ];

    int? validYear = years.contains(_selectedYear) ? _selectedYear : years.first;
    int? validMonth = months.contains(_selectedMonth) ? _selectedMonth : 1;
    int? validDay = _selectedDay ?? -1;
    if (validDay != -1 && validDay! > maxDay) validDay = maxDay;

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
          value: validYear!,
          items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y年'))).toList(),
          onChanged: _isSaving ? null : (v) => setState(() { _selectedYear = v; _ocrErrorMessage = null; }),
        ),
        const SizedBox(width: 8),
        buildDropdown<int>(
          label: '月',
          value: validMonth!,
          items: months.map((m) => DropdownMenuItem(value: m, child: Text('$m月'))).toList(),
          onChanged: _isSaving ? null : (v) => setState(() { _selectedMonth = v; _ocrErrorMessage = null; }),
        ),
        const SizedBox(width: 8),
        buildDropdown<int>(
          label: '日',
          value: validDay!,
          items: dayItems,
          onChanged: _isSaving ? null : (v) => setState(() { _selectedDay = v; _ocrErrorMessage = null; }),
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
    final shopId = ref.read(currentShopIdProvider);

    if (shopId.isEmpty) {
      setState(() => _ocrErrorMessage = '店舗が未選択のため登録できません。');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final newItem = SnackItem(
        name: name,
        expiry: expiry,
        janCode: (_janCode?.isNotEmpty == true) ? _janCode!.trim() : null,
        price: price,
      );

      final savedItem = await ref.read(snackRepositoryProvider).addSnack(newItem);
      _updateJanMasterIfNeeded(savedItem);

      if (!mounted) return;

      final isKeepAdding = ref.read(appSettingsProvider).isKeepAddingEnabled;

      if (isKeepAdding) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登録しました'), duration: Duration(seconds: 2)),
        );
        _resetFormForNext();
      } else {
        Navigator.of(context).pop(savedItem);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _ocrErrorMessage = '登録に失敗しました: $e';
      });
    }
  }

  Future<void> _updateJanMasterIfNeeded(SnackItem snack) async {
    final jan = snack.janCode;
    if (jan == null || jan.isEmpty) return;
    try {
      final user = ref.read(appUserStreamProvider).value;
      final repo = ref.read(janMasterRepositoryProvider);
      await repo.upsertJan(
        janCode: jan,
        name: snack.name,
        price: snack.price,
        userId: user?.uid ?? 'anonymous',
      );
    } catch (_) {}
  }

  Future<void> _openBarcodeScannerModal(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.65,
          child: Column(
            children: [
              AppBar(title: const Text('バーコードをスキャン'), automaticallyImplyLeading: false, actions: [CloseButton()]),
              Expanded(
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final val = barcodes.first.rawValue;
                      if (val != null) Navigator.of(ctx).pop(val);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result != null && mounted) {
      setState(() => _janCode = result);
      await _loadJanMasterForJanCode(result);
    }
  }

  Future<void> _loadJanMasterForJanCode(String janCode) async {
    setState(() => _isLoadingJanMaster = true);
    try {
      final entry = await ref.read(janMasterRepositoryProvider).fetchJan(janCode);
      if (mounted) {
        setState(() {
          _isLoadingJanMaster = false;
          _masterName = entry?.name;
          _masterPrice = entry?.price;
        });
        _applyMasterToControllersIfEmpty();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingJanMaster = false);
    }
  }

  void _applyMasterToControllersIfEmpty() {
    if (_masterName != null && _nameController.text.isEmpty) {
      _nameController.text = _masterName!;
    }
    if (_masterPrice != null && _priceController.text.isEmpty) {
      _priceController.text = _masterPrice.toString();
    }
  }

  Future<void> _showFrequentPricesManageDialog(BuildContext context, String shopId) async {
    // ★ 追加: ダイアログを開く前にキーボードを閉じる
    FocusScope.of(context).unfocus();

    final doc = await FirebaseFirestore.instance.collection('shops').doc(shopId).get();
    final rawList = doc.data()?['frequentPrices'] as List<dynamic>? ?? [];
    final currentPrices = rawList.cast<int>()..sort();

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => _FrequentPricesDialog(
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

class _FrequentPricesDialog extends StatefulWidget {
  const _FrequentPricesDialog({required this.initialPrices, required this.onSave});
  final List<int> initialPrices;
  final ValueChanged<List<int>> onSave;

  @override
  State<_FrequentPricesDialog> createState() => _FrequentPricesDialogState();
}

class _FrequentPricesDialogState extends State<_FrequentPricesDialog> {
  late List<int> _prices;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prices = List.of(widget.initialPrices);
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
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            Wrap(
              spacing: 8,
              children: _prices.map((p) => Chip(
                label: Text('$p円'),
                onDeleted: () => _removePrice(p),
              )).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
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