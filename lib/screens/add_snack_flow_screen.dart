import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/snack_item.dart';
import 'package:expiry_date/core/jan_master/jan_master_repository.dart';

enum AddSnackStep {
  scanBarcode,
  captureExpiry,
  editDetails,
}

class AddSnackFlowScreen extends ConsumerStatefulWidget {
  const AddSnackFlowScreen({super.key});

  @override
  ConsumerState<AddSnackFlowScreen> createState() =>
      _AddSnackFlowScreenState();
}

class _AddSnackFlowScreenState extends ConsumerState<AddSnackFlowScreen> {
  AddSnackStep _step = AddSnackStep.scanBarcode;
  bool _isScanningBarcode = true;

  String? _janCode;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  final ImagePicker _picker = ImagePicker();
  bool _isRunningOcr = false;
  String? _ocrRawText;
  String? _ocrErrorMessage;
  XFile? _expiryImage;

  // 賞味期限（プルダウン＋カレンダー用）
  int? _selectedYear;
  int? _selectedMonth;
  int? _selectedDay;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  DateTime? _buildSelectedExpiry() {
    if (_selectedYear == null ||
        _selectedMonth == null ||
        _selectedDay == null) {
      return null;
    }
    try {
      return DateTime(_selectedYear!, _selectedMonth!, _selectedDay!);
    } catch (_) {
      return null;
    }
  }

  void _applyExpiryFromDate(DateTime date) {
    _selectedYear = date.year;
    _selectedMonth = date.month;
    _selectedDay = date.day;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ここはデフォルト(true)のまま：キーボード表示時に body の高さが縮み、
      // 下部のボタン列（editDetailsで表示）が自動的にキーボードの上に来る。
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('商品を追加'),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildCurrentStep(context),
        ),
      ),
    );
  }

  Widget _buildCurrentStep(BuildContext context) {
    switch (_step) {
      case AddSnackStep.scanBarcode:
        return _buildScanBarcodeStep(context);
      case AddSnackStep.captureExpiry:
        return _buildCaptureExpiryStep(context);
      case AddSnackStep.editDetails:
        return _buildEditDetailsStep(context);
    }
  }

  // 1. バーコード読み取りステップ
  Widget _buildScanBarcodeStep(BuildContext context) {
    return Column(
      key: const ValueKey('scan_barcode'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'まずは商品のバーコードを読み取って、JANコードを取得します。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: MobileScanner(
            controller: MobileScannerController(
              detectionSpeed: DetectionSpeed.noDuplicates,
              facing: CameraFacing.back,
            ),
            onDetect: (capture) {
              if (!_isScanningBarcode) return;

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;

              final String? rawValue = barcodes.first.rawValue;
              if (rawValue == null || rawValue.isEmpty) {
                return;
              }

              _isScanningBarcode = false;

              setState(() {
                _janCode = rawValue;
                _step = AddSnackStep.captureExpiry;
              });

              // Firestore 上の JAN マスタから、商品名・売価を自動入力する
              _loadJanMasterForJanCode(rawValue);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('JANコードを取得しました: $rawValue')),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'バーコードがどうしても読み取れない場合は、後でJANコードをメモしておき、商品名だけで登録しても構いません。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _isScanningBarcode = false;
                    _janCode = null;
                    _step = AddSnackStep.captureExpiry;
                  });
                },
                child: const Text('バーコード読み取りをスキップする'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 2. 賞味期限撮影＋OCRステップ
  //
  // 撮影→OCR終了後、そのまま商品情報入力画面（editDetails）へ遷移。
  Widget _buildCaptureExpiryStep(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('capture_expiry'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '次に、賞味期限の部分を撮影してOCRで日付を読み取ります。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            '賞味期限の文字がはっきり写るように、ピントと明るさを調整してください。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (_expiryImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: kIsWeb
                    ? Image.network(
                  _expiryImage!.path,
                  fit: BoxFit.cover,
                )
                    : Image.file(
                  File(_expiryImage!.path),
                  fit: BoxFit.cover,
                ),
              ),
            )
          else
            Container(
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              alignment: Alignment.center,
              child: const Text(
                'まだ画像がありません。\n「カメラを起動して撮影する」を押してください。',
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 16),
          if (_isRunningOcr)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            if (_ocrErrorMessage != null) ...[
              Text(
                _ocrErrorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_ocrRawText != null && _ocrRawText!.isNotEmpty) ...[
              Text(
                'OCRで読み取ったテキスト（参考用）',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Theme.of(context).colorScheme.surfaceVariant,
                ),
                child: Text(
                  _ocrRawText!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _isRunningOcr ? null : _onTapCaptureExpiry,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(
              _expiryImage == null ? 'カメラを起動して撮影する' : 'もう一度撮影する',
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isRunningOcr
                ? null
                : () {
              setState(() {
                _step = AddSnackStep.editDetails;
                _ocrErrorMessage =
                'OCRをスキップしたため、賞味期限は手動で選択してください。';
              });
            },
            child: const Text('OCRを使わずに手入力する'),
          ),
        ],
      ),
    );
  }

  // 3. 商品名／賞味期限／売価の入力ステップ
  //
  // ここが今回の修正ポイント：
  // - ボタン列（キャンセル/商品を追加）をスクロール領域の外に出し、
  //   キーボード表示時でも常に押せるようにする。
  // - その代わり、フォームは Expanded + ScrollView で自然にスクロール可能にする。
  Widget _buildEditDetailsStep(BuildContext context) {
    final now = DateTime.now();
    final years = List<int>.generate(6, (i) => now.year + i); // 今年〜+5年
    final months = List<int>.generate(12, (i) => i + 1);

    final int baseYear = _selectedYear ?? now.year;
    final int baseMonth = _selectedMonth ?? 1;
    final int maxDay = _daysInMonth(baseYear, baseMonth);
    final days = List<int>.generate(maxDay, (i) => i + 1);

    return Column(
      key: const ValueKey('edit_details'),
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              FocusScope.of(context).unfocus();
            },
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_janCode != null) ...[
                      Text(
                        'JANコード',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _janCode!,
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
                    const SizedBox(height: 24),
                    Text(
                      '賞味期限',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    if (_ocrErrorMessage != null) ...[
                      Text(
                        _ocrErrorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: const ValueKey('year_dropdown'),
                            decoration: const InputDecoration(
                              labelText: '年',
                            ),
                            items: years
                                .map(
                                  (y) => DropdownMenuItem<int>(
                                value: y,
                                child: Text('$y年'),
                              ),
                            )
                                .toList(),
                            initialValue: _selectedYear,
                            onChanged: (value) {
                              setState(() {
                                _selectedYear = value;
                                if (_selectedMonth != null &&
                                    _selectedDay != null) {
                                  final newMaxDay = _daysInMonth(
                                      _selectedYear!, _selectedMonth!);
                                  if (_selectedDay! > newMaxDay) {
                                    _selectedDay = newMaxDay;
                                  }
                                }
                              });
                            },
                            validator: (value) {
                              if (value == null) {
                                return '年を選択してください';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: const ValueKey('month_dropdown'),
                            decoration: const InputDecoration(
                              labelText: '月',
                            ),
                            items: months
                                .map(
                                  (m) => DropdownMenuItem<int>(
                                value: m,
                                child: Text('$m月'),
                              ),
                            )
                                .toList(),
                            initialValue: _selectedMonth,
                            onChanged: (value) {
                              setState(() {
                                _selectedMonth = value;
                                if (_selectedYear != null &&
                                    _selectedDay != null) {
                                  final newMaxDay = _daysInMonth(
                                      _selectedYear!, _selectedMonth!);
                                  if (_selectedDay! > newMaxDay) {
                                    _selectedDay = newMaxDay;
                                  }
                                }
                              });
                            },
                            validator: (value) {
                              if (value == null) {
                                return '月を選択してください';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: const ValueKey('day_dropdown'),
                            decoration: const InputDecoration(
                              labelText: '日',
                            ),
                            items: days
                                .map(
                                  (d) => DropdownMenuItem<int>(
                                value: d,
                                child: Text('$d日'),
                              ),
                            )
                                .toList(),
                            initialValue: _selectedDay != null &&
                                _selectedDay! <= maxDay
                                ? _selectedDay
                                : null,
                            onChanged: (value) {
                              setState(() {
                                _selectedDay = value;
                              });
                            },
                            validator: (value) {
                              if (value == null) {
                                return '日を選択してください';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            _onTapSelectDateWithCalendar(context),
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('カレンダーから選択'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _isRunningOcr ? null : _onTapCaptureExpiry,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('賞味期限をもう一度撮影する'),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                      onFieldSubmitted: (_) {
                        _onSubmit();
                      },
                    ),
                    const SizedBox(height: 24),
                    // 末尾が詰まりすぎないように少し余白
                    const SizedBox(height: 8),
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
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 0.8,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('キャンセル'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _onSubmit(),
                    child: const Text('商品を追加'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // カレンダーから日付を選択
  Future<void> _onTapSelectDateWithCalendar(BuildContext context) async {
    final now = DateTime.now();
    final initial =
        _buildSelectedExpiry() ?? DateTime(now.year, now.month, now.day);
    final first = DateTime(now.year - 1, 1, 1);
    final last = DateTime(now.year + 10, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );

    if (picked != null) {
      setState(() {
        _applyExpiryFromDate(picked);
        _ocrErrorMessage = null;
      });
    }
  }

  // 賞味期限撮影＋OCR
  //
  // 撮影して OCR → プルダウンに値を反映し、そのまま editDetails へ。
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
        _ocrRawText = null;
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

      _expiryImage = image;

      final inputImage = InputImage.fromFilePath(image.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final RecognizedText recognizedText =
      await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final String text = recognizedText.text;
      final DateTime? parsed = _tryParseExpiryFromText(text);

      setState(() {
        _isRunningOcr = false;
        _ocrRawText = text;
        if (parsed != null) {
          _applyExpiryFromDate(parsed);
          _ocrErrorMessage = null;
        } else {
          _ocrErrorMessage =
          '賞味期限の日付を自動で特定できませんでした。プルダウンまたはカレンダーから選択してください。';
        }
      });

      if (!mounted) return;

      // 撮影後は確認画面を挟まず、そのまま商品情報入力画面へ。
      setState(() {
        _step = AddSnackStep.editDetails;
      });
    } catch (e) {
      setState(() {
        _isRunningOcr = false;
        _ocrErrorMessage = 'OCR中にエラーが発生しました: $e';
      });
    }
  }

  // 「商品を追加」押下時
  Future<void> _onSubmit() async {
    FocusScope.of(context).unfocus();

    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final DateTime? expiry = _buildSelectedExpiry();
    if (expiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('賞味期限を選択してください。')),
      );
      return;
    }

    final String name = _nameController.text.trim();
    final String priceText = _priceController.text.trim();
    int? price;

    if (priceText.isNotEmpty) {
      price = int.tryParse(priceText.replaceAll(',', ''));
      if (price == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('売価には数値を入力してください。')),
        );
        return;
      }
    }

    final snack = SnackItem(
      name: name,
      expiry: expiry,
      janCode: _janCode,
      price: price,
    );

    // JANコードがある場合は、JANマスタを更新（最後に入力した値として保存）
    await _updateJanMasterIfNeeded(snack);

    if (!mounted) return;
    Navigator.of(context).pop(snack);
  }

  /// JANコードに対応する JAN マスタ情報を読み込み、
  /// 商品名・売価の入力欄を自動補完する。
  Future<void> _loadJanMasterForJanCode(String janCode) async {
    try {
      final repo = ref.read(janMasterRepositoryProvider);
      final entry = await repo.fetchJan(janCode);

      if (!mounted || entry == null) return;

      setState(() {
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = entry.name;
        }
        if (entry.price != null) {
          _priceController.text = entry.price.toString();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('過去の登録データを読み込みました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('JANマスタの読み込みに失敗しました: $e')),
      );
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('JANマスタの更新に失敗しました: $e')),
      );
    }
  }

  // OCR結果のテキストから日付っぽい部分を抜き出してDateTimeにする
  //
  // 対応形式:
  // - 2025/12/31, 2025-12-31, 2025.12.31
  // - 25/12/31, 25-12-31 → 2025/12/31
  // - 2027/07, 2027-07, 2027.7 → 2027/07/末日
  // - 27/07, 27-07, 27.7 → 2027/07/末日
  DateTime? _tryParseExpiryFromText(String text) {
    final normalized = text
        .replaceAll('年', '/')
        .replaceAll('月', '/')
        .replaceAll('日', '')
        .replaceAll(RegExp(r'[^0-9/.\-]'), ' ');

    // 例：2025/12/31, 2025-12-31, 2025.12.31
    final match4 = RegExp(r'(\d{4})[./\-](\d{1,2})[./\-](\d{1,2})')
        .firstMatch(normalized);
    if (match4 != null) {
      final year = int.parse(match4.group(1)!);
      final month = int.parse(match4.group(2)!);
      final day = int.parse(match4.group(3)!);
      if (_isValidYmd(year, month, day)) {
        return DateTime(year, month, day);
      }
    }

    // 例：25/12/31, 25-12-31 など（西暦下2桁扱いで 2000+xx とみなす）
    final match2 = RegExp(r'(\d{2})[./\-](\d{1,2})[./\-](\d{1,2})')
        .firstMatch(normalized);
    if (match2 != null) {
      final twoDigitYear = int.parse(match2.group(1)!);
      final year = 2000 + twoDigitYear;
      final month = int.parse(match2.group(2)!);
      final day = int.parse(match2.group(3)!);
      if (_isValidYmd(year, month, day)) {
        return DateTime(year, month, day);
      }
    }

    // 4桁年 + 月（例: 2027/07, 2027-07, 2027.7）→ 月末日扱い
    final matchYearMonth4 =
    RegExp(r'(\d{4})[./\-](\d{1,2})').firstMatch(normalized);
    if (matchYearMonth4 != null) {
      final year = int.parse(matchYearMonth4.group(1)!);
      final month = int.parse(matchYearMonth4.group(2)!);
      if (month >= 1 && month <= 12) {
        final lastDay = _lastDayOfMonth(year, month);
        if (_isValidYmd(year, month, lastDay)) {
          return DateTime(year, month, lastDay);
        }
      }
    }

    // 2桁年 + 月（例: 27/07, 27-07, 27.7）→ 20xx 年 + 月末日扱い
    final matchYearMonth2 =
    RegExp(r'(\d{2})[./\-](\d{1,2})').firstMatch(normalized);
    if (matchYearMonth2 != null) {
      final twoDigitYear = int.parse(matchYearMonth2.group(1)!);
      final year = 2000 + twoDigitYear;
      final month = int.parse(matchYearMonth2.group(2)!);
      if (month >= 1 && month <= 12) {
        final lastDay = _lastDayOfMonth(year, month);
        if (_isValidYmd(year, month, lastDay)) {
          return DateTime(year, month, lastDay);
        }
      }
    }

    return null;
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

  /// 与えられた [year], [month] の月末日（28〜31 のいずれか）を返す。
  int _lastDayOfMonth(int year, int month) {
    final lastDate = DateTime(year, month + 1, 0);
    return lastDate.day;
  }

  int _daysInMonth(int year, int month) {
    return _lastDayOfMonth(year, month);
  }
}
