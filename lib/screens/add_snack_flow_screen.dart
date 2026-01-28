import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:expiry_date/core/jan_master/jan_master_repository.dart';
import 'package:expiry_date/core/user/user_providers.dart';
import '../models/snack_item.dart';

class AddSnackFlowScreen extends ConsumerStatefulWidget {
  const AddSnackFlowScreen({super.key});

  @override
  ConsumerState<AddSnackFlowScreen> createState() => _AddSnackFlowScreenState();
}

class _AddSnackFlowScreenState extends ConsumerState<AddSnackFlowScreen> {
  // ======================
  // 入力状態
  // ======================
  String? _janCode;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // 連続登録
  bool _keepAdding = false;

  // Firestore保存中
  bool _isSaving = false;

  // ======================
  // OCR
  // ======================
  final ImagePicker _picker = ImagePicker();
  bool _isRunningOcr = false;
  String? _ocrErrorMessage;

  // ======================
  // JANマスタ取得（自動入力のみ）
  // ======================
  bool _isLoadingJanMaster = false;
  String? _janMasterErrorMessage;
  String? _masterName;
  int? _masterPrice;

  // ======================
  // 賞味期限（プルダウン）
  // day は -1 を「末日」として扱う
  // ======================
  int? _selectedYear;
  int? _selectedMonth;
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    _setExpiryToDefaultValues();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  // ======================
  // 期限：デフォルト（翌月末日）
  // ======================
  void _setExpiryToDefaultValues() {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    _selectedYear = nextMonth.year;
    _selectedMonth = nextMonth.month;
    _selectedDay = -1; // 末日
  }

  int _lastDayOfMonth(int year, int month) {
    final lastDate = DateTime(year, month + 1, 0);
    return lastDate.day;
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
    _selectedYear = date.year;
    _selectedMonth = date.month;
    _selectedDay = date.day;
  }

  // ======================
  // 連続登録時リセット
  // ======================
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

  // ======================
  // UI
  // ======================
  @override
  Widget build(BuildContext context) {
    // 画面全体のフォントを少し大きく
    final baseTheme = Theme.of(context);
    final bigTheme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(fontSizeFactor: 1.12),
    );

    return Theme(
      data: bigTheme,
      child: Builder(
        builder: (context) {
          final shopId = ref.watch(currentShopIdProvider);

          return Scaffold(
            resizeToAvoidBottomInset: true,
            appBar: AppBar(
              title: const Text('商品を追加'),
            ),
            body: SafeArea(
              child: Column(
                children: [
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

                              // 商品名（マスタで自動入力される想定：先に置く）
                              TextFormField(
                                controller: _nameController,
                                style: const TextStyle(
                                  fontSize: 22, // ← さらに大きく
                                  fontWeight: FontWeight.w600,
                                ),
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

                              // 売価（右に「よく使う売価」プルダウン。中身はまだ空）
                              _buildPriceRow(context),

                              const SizedBox(height: 20),

                              // 賞味期限（最後に置く）
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '賞味期限',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'カメラで読み取る（OCR）',
                                    onPressed: (_isRunningOcr || _isSaving) ? null : _onTapCaptureExpiry,
                                    icon: const Icon(Icons.camera_alt_outlined),
                                  ),
                                ],
                              ),
                              if (_ocrErrorMessage != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _ocrErrorMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              _buildExpiryDropdowns(context),

                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // フッター（連続登録 + ボタン）
                  SafeArea(
                    top: false,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            width: 0.8,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: SizedBox.shrink(),
                              ),
                              const Text('連続登録'),
                              const SizedBox(width: 8),
                              Checkbox(
                                value: _keepAdding,
                                onChanged: _isSaving
                                    ? null
                                    : (v) => setState(() => _keepAdding = (v ?? false)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(54),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    foregroundColor: Colors.grey, // ← 文字色をグレーに
                                  ),
                                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                                  child: const Text('キャンセル'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.redAccent, // ← 登録ボタン赤
                                    minimumSize: const Size.fromHeight(54),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  onPressed: _isSaving ? null : () => _onSubmit(),
                                  child: _isSaving
                                      ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
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

  Widget _buildJanSection(BuildContext context, String shopId) {
    final hasJan = _janCode != null && _janCode!.trim().isNotEmpty;

    final bool canScan = !_isSaving && !_isRunningOcr && shopId.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceVariant,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'JANコード',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      hasJan ? _janCode! : '未入力',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent, // ← スキャンボタン赤
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: (canScan) ? () => _openBarcodeScannerModal(context) : null,
                  icon: const Icon(Icons.qr_code_scanner, size: 24),
                  label: Text(_isLoadingJanMaster ? '取得中…' : 'スキャン'),
                ),
              ),
            ],
          ),
          if (shopId.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '店舗が未選択のためスキャン/登録できません。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
            ),
          ],
          if (_janMasterErrorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _janMasterErrorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceRow(BuildContext context) {
    // 今はまだ空（設定＋SharedPreferences実装は後続）
    final frequentPrices = <int>[];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _priceController,
            style: const TextStyle(
              fontSize: 22, // ← さらに大きく
              fontWeight: FontWeight.w600,
            ),
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
            onFieldSubmitted: (_) => _onSubmit(),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<int>(
            decoration: const InputDecoration(
              labelText: 'よく使う',
            ),
            items: frequentPrices
                .map(
                  (p) => DropdownMenuItem<int>(
                value: p,
                child: Text('$p円'),
              ),
            )
                .toList(),
            value: null,
            hint: const Text('未設定'),
            onChanged: (frequentPrices.isEmpty || _isSaving)
                ? null
                : (value) {
              if (value == null) return;
              setState(() {
                _priceController.text = value.toString();
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExpiryDropdowns(BuildContext context) {
    final now = DateTime.now();

    // 要件通り：現在年〜5年先まで（計6個）
    final years = <int>[for (int y = now.year; y <= now.year + 5; y++) y];
    final months = List<int>.generate(12, (i) => i + 1);

    final baseYear = _selectedYear ?? now.year;
    final baseMonth = _selectedMonth ?? 1;
    final maxDay = _daysInMonth(baseYear, baseMonth);

    final dayItems = <DropdownMenuItem<int>>[
      const DropdownMenuItem<int>(
        value: -1,
        child: Text('末日'),
      ),
      ...List<int>.generate(maxDay, (i) => i + 1).map(
            (d) => DropdownMenuItem<int>(
          value: d,
          child: Text('$d日'),
        ),
      ),
    ];

    final yearValue = (_selectedYear != null && years.contains(_selectedYear)) ? _selectedYear : years.first;
    final monthValue = (_selectedMonth != null && months.contains(_selectedMonth)) ? _selectedMonth : 1;
    final dayValue = _selectedDay ?? -1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            decoration: const InputDecoration(labelText: '年'),
            items: years
                .map(
                  (y) => DropdownMenuItem<int>(
                value: y,
                child: Text('$y年'),
              ),
            )
                .toList(),
            value: yearValue,
            onChanged: (_isSaving || _isRunningOcr)
                ? null
                : (value) {
              setState(() {
                _selectedYear = value;
                _ocrErrorMessage = null;

                if (_selectedYear != null && _selectedMonth != null && _selectedDay != null && _selectedDay != -1) {
                  final newMax = _daysInMonth(_selectedYear!, _selectedMonth!);
                  if (_selectedDay! > newMax) {
                    _selectedDay = newMax;
                  }
                }
              });
            },
            validator: (value) => (value == null) ? '年を選択してください' : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<int>(
            decoration: const InputDecoration(labelText: '月'),
            items: months
                .map(
                  (m) => DropdownMenuItem<int>(
                value: m,
                child: Text('$m月'),
              ),
            )
                .toList(),
            value: monthValue,
            onChanged: (_isSaving || _isRunningOcr)
                ? null
                : (value) {
              setState(() {
                _selectedMonth = value;
                _ocrErrorMessage = null;

                if (_selectedYear != null && _selectedMonth != null && _selectedDay != null && _selectedDay != -1) {
                  final newMax = _daysInMonth(_selectedYear!, _selectedMonth!);
                  if (_selectedDay! > newMax) {
                    _selectedDay = newMax;
                  }
                }
              });
            },
            validator: (value) => (value == null) ? '月を選択してください' : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<int>(
            decoration: const InputDecoration(labelText: '日'),
            items: dayItems,
            value: dayValue,
            onChanged: (_isSaving || _isRunningOcr)
                ? null
                : (value) {
              setState(() {
                _selectedDay = value;
                _ocrErrorMessage = null;
              });
            },
            validator: (value) => (value == null) ? '日を選択してください' : null,
          ),
        ),
      ],
    );
  }

  // ======================
  // バーコードスキャン（モーダル）
  // ======================
  Future<void> _openBarcodeScannerModal(BuildContext context) async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web上ではバーコードスキャンは未対応です。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) {
        bool isDetecting = true;

        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'バーコードをスキャン',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: MobileScanner(
                  controller: MobileScannerController(
                    detectionSpeed: DetectionSpeed.noDuplicates,
                    facing: CameraFacing.back,
                  ),
                  onDetect: (capture) {
                    if (!isDetecting) return;

                    final barcodes = capture.barcodes;
                    if (barcodes.isEmpty) return;

                    final rawValue = barcodes.first.rawValue;
                    if (rawValue == null || rawValue.trim().isEmpty) return;

                    isDetecting = false;
                    Navigator.of(ctx).pop(rawValue.trim());
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'うまく読めない場合は、明るい場所でピントを合わせてください。',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (result == null || result.trim().isEmpty) return;

    setState(() {
      _janCode = result.trim();
      _janMasterErrorMessage = null;
      _masterName = null;
      _masterPrice = null;
      _ocrErrorMessage = null;
    });

    await _loadJanMasterForJanCode(result.trim());
  }

  /// JANコードに対応するJANマスタを読み込み、（空欄なら）フォームへ自動入力する
  Future<void> _loadJanMasterForJanCode(String janCode) async {
    setState(() {
      _isLoadingJanMaster = true;
      _janMasterErrorMessage = null;
      _masterName = null;
      _masterPrice = null;
    });

    try {
      final repo = ref.read(janMasterRepositoryProvider);
      final entry = await repo.fetchJan(janCode);

      if (!mounted) return;

      if (entry == null) {
        setState(() {
          _isLoadingJanMaster = false;
          _janMasterErrorMessage = null;
          _masterName = null;
          _masterPrice = null;
        });
        return;
      }

      setState(() {
        _isLoadingJanMaster = false;
        _masterName = entry.name;
        _masterPrice = entry.price;
      });

      _applyMasterToControllersIfEmpty();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingJanMaster = false;
        _janMasterErrorMessage = 'マスタの読み込みに失敗しました: $e';
      });
    }
  }

  void _applyMasterToControllersIfEmpty() {
    if (!mounted) return;

    final name = _masterName;
    final price = _masterPrice;

    if (name != null && name.trim().isNotEmpty) {
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = name;
      }
    }
    if (price != null) {
      if (_priceController.text.trim().isEmpty) {
        _priceController.text = price.toString();
      }
    }
  }

  // ======================
  // OCR（撮影→解析→プルダウンへ反映。プレビュー等はしない）
  // ======================
  Future<void> _onTapCaptureExpiry() async {
    if (kIsWeb) {
      setState(() {
        _ocrErrorMessage = 'Web上ではカメラ撮影とOCRは未対応です。';
      });
      return;
    }

    try {
      setState(() {
        _isRunningOcr = true;
        _ocrErrorMessage = null;
      });

      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (image == null) {
        setState(() {
          _isRunningOcr = false;
        });
        return;
      }

      final inputImage = InputImage.fromFilePath(image.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );

      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final text = recognizedText.text;
      final parsed = _tryParseExpiryFromText(text);

      setState(() {
        _isRunningOcr = false;

        if (parsed != null) {
          _applyExpiryFromDate(parsed);
          _ocrErrorMessage = null;
        } else {
          _ocrErrorMessage = '賞味期限の日付を自動で特定できませんでした。プルダウンから選択してください。';
        }
      });
    } catch (e) {
      setState(() {
        _isRunningOcr = false;
        _ocrErrorMessage = 'OCR中にエラーが発生しました: $e';
      });
    }
  }

  // ======================
  // SnackBar（ボタンを隠さないよう上に出す）
  // ======================
  void _showSavedSnackBar() {
    final messenger = ScaffoldMessenger.of(context);
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    final marginBottom = bottomSafe + 140;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('登録しました'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: EdgeInsets.fromLTRB(16, 0, 16, marginBottom),
      ),
    );
  }

  // ======================
  // 登録（Firestoreに保存）
  // ======================
  Future<void> _onSubmit() async {
    FocusScope.of(context).unfocus();

    if (_isSaving) return;

    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final expiry = _buildSelectedExpiry();
    if (expiry == null) {
      setState(() {
        _ocrErrorMessage = '賞味期限を選択してください。';
      });
      return;
    }

    final name = _nameController.text.trim();
    final priceText = _priceController.text.trim();
    int? price;

    if (priceText.isNotEmpty) {
      price = int.tryParse(priceText.replaceAll(',', '').trim());
      if (price == null) {
        setState(() {
          _ocrErrorMessage = '売価には数値を入力してください。';
        });
        return;
      }
    }

    final shopId = ref.read(currentShopIdProvider);
    if (shopId.isEmpty) {
      setState(() {
        _ocrErrorMessage = '店舗が未選択のため登録できません。';
      });
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final db = FirebaseFirestore.instance;

      await db.collection('shops').doc(shopId).collection('snacks').add({
        'name': name,
        'expiry': Timestamp.fromDate(expiry),
        'janCode': (_janCode != null && _janCode!.trim().isNotEmpty) ? _janCode!.trim() : null,
        'price': price,
        'isArchived': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUserId': user?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUserId': user?.uid,
      });

      final snack = SnackItem(
        name: name,
        expiry: expiry,
        janCode: (_janCode != null && _janCode!.trim().isNotEmpty) ? _janCode!.trim() : null,
        price: price,
      );
      await _updateJanMasterIfNeeded(snack);

      if (!mounted) return;

      if (_keepAdding) {
        setState(() {
          _isSaving = false;
        });

        _showSavedSnackBar();
        _resetFormForNext();
        return;
      }

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _ocrErrorMessage = '登録に失敗しました: $e';
      });
    }
  }

  /// JANマスタへの upsert（JANコードが無い場合は何もしない）。
  Future<void> _updateJanMasterIfNeeded(SnackItem snack) async {
    final jan = snack.janCode;
    if (jan == null || jan.isEmpty) {
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final repo = ref.read(janMasterRepositoryProvider);
      await repo.upsertJan(
        janCode: jan,
        name: snack.name,
        price: snack.price,
        userId: user?.uid ?? 'anonymous',
      );
    } catch (_) {
      // SnackBar禁止のため黙って握りつぶす（必要ならどこかにログ/画面内表示へ）
    }
  }

  // ======================
  // OCR解析（既存ロジック流用）
  // ======================
  DateTime? _tryParseExpiryFromText(String text) {
    final now = DateTime.now();

    final normalized = _normalizeOcrTextForParse(text);
    final fixed = _fixDigits(normalized);

    final candidates = <DateTime>[];

    for (final m in RegExp(r'\b(\d{4})(\d{2})(\d{2})\b').allMatches(fixed)) {
      final year = int.tryParse(m.group(1)!);
      final month = int.tryParse(m.group(2)!);
      final day = int.tryParse(m.group(3)!);
      if (year == null || month == null || day == null) continue;
      if (_isValidYmd(year, month, day)) {
        final dt = DateTime(year, month, day);
        if (_isPlausibleExpiry(dt, now)) candidates.add(dt);
      }
    }

    for (final m in RegExp(r'\b(\d{2})(\d{2})(\d{2})\b').allMatches(fixed)) {
      final yy = int.tryParse(m.group(1)!);
      final month = int.tryParse(m.group(2)!);
      final day = int.tryParse(m.group(3)!);
      if (yy == null || month == null || day == null) continue;
      final year = 2000 + yy;
      if (_isValidYmd(year, month, day)) {
        final dt = DateTime(year, month, day);
        if (_isPlausibleExpiry(dt, now)) candidates.add(dt);
      }
    }

    for (final m in RegExp(r'\b(\d{4})\s+(\d{1,2})\s+(\d{1,2})\b').allMatches(fixed)) {
      final year = int.tryParse(m.group(1)!);
      final month = int.tryParse(m.group(2)!);
      final day = int.tryParse(m.group(3)!);
      if (year == null || month == null || day == null) continue;
      if (_isValidYmd(year, month, day)) {
        final dt = DateTime(year, month, day);
        if (_isPlausibleExpiry(dt, now)) candidates.add(dt);
      }
    }

    for (final m in RegExp(r'\b(\d{2})\s+(\d{1,2})\s+(\d{1,2})\b').allMatches(fixed)) {
      final yy = int.tryParse(m.group(1)!);
      final month = int.tryParse(m.group(2)!);
      final day = int.tryParse(m.group(3)!);
      if (yy == null || month == null || day == null) continue;
      final year = 2000 + yy;
      if (_isValidYmd(year, month, day)) {
        final dt = DateTime(year, month, day);
        if (_isPlausibleExpiry(dt, now)) candidates.add(dt);
      }
    }

    for (final m in RegExp(r'\b(\d{4})\s+(\d{1,2})\b').allMatches(fixed)) {
      final year = int.tryParse(m.group(1)!);
      final month = int.tryParse(m.group(2)!);
      if (year == null || month == null) continue;
      if (month < 1 || month > 12) continue;
      final lastDay = _lastDayOfMonth(year, month);
      if (_isValidYmd(year, month, lastDay)) {
        final dt = DateTime(year, month, lastDay);
        if (_isPlausibleExpiry(dt, now)) candidates.add(dt);
      }
    }

    for (final m in RegExp(r'\b(\d{2})\s+(\d{1,2})\b').allMatches(fixed)) {
      final yy = int.tryParse(m.group(1)!);
      final month = int.tryParse(m.group(2)!);
      if (yy == null || month == null) continue;
      final year = 2000 + yy;
      if (month < 1 || month > 12) continue;
      final lastDay = _lastDayOfMonth(year, month);
      if (_isValidYmd(year, month, lastDay)) {
        final dt = DateTime(year, month, lastDay);
        if (_isPlausibleExpiry(dt, now)) candidates.add(dt);
      }
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => _expiryScore(a, now).compareTo(_expiryScore(b, now)));
    return candidates.first;
  }

  String _normalizeOcrTextForParse(String text) {
    final s = text
        .replaceAll('年', ' ')
        .replaceAll('月', ' ')
        .replaceAll('日', ' ')
        .replaceAll(RegExp(r'[\/\.\-\,，、]'), ' ')
        .replaceAll(RegExp(r'[^0-9A-Za-z\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return s;
  }

  String _fixDigits(String s) {
    final upper = s.toUpperCase();

    const map = <String, String>{
      'O': '0',
      'D': '0',
      'Q': '0',
      'I': '1',
      'L': '1',
      '|': '1',
      '!': '1',
      'Z': '2',
      'S': '5',
      'B': '8',
    };

    final buf = StringBuffer();
    for (final ch in upper.split('')) {
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }

  bool _isPlausibleExpiry(DateTime dt, DateTime now) {
    final min = DateTime(now.year - 10, 1, 1);
    final max = DateTime(now.year + 30, 12, 31);
    return !dt.isBefore(min) && !dt.isAfter(max);
  }

  int _expiryScore(DateTime dt, DateTime now) {
    final diffDays = dt.difference(now).inDays;
    if (diffDays >= 0) {
      return diffDays;
    }
    return 100000 + diffDays.abs();
  }

  bool _isValidYmd(int year, int month, int day) {
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;

    try {
      final dt = DateTime(year, month, day);
      return dt.year == year && dt.month == month && dt.day == day;
    } catch (_) {
      return false;
    }
  }
}
