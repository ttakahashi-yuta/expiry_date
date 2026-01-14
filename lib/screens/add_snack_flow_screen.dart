import 'dart:io';
import 'dart:math';

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
  ConsumerState<AddSnackFlowScreen> createState() => _AddSnackFlowScreenState();
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

  // ===== OCR デバッグ用（開発時のみ表示）
  // TODO: リリース前に削除/無効化する（kDebugModeで隠れているが念のため）
  String? _ocrNormalizedForDebug;
  DateTime? _ocrParsedForDebug;

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
    if (_selectedYear == null || _selectedMonth == null || _selectedDay == null) {
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
                _ocrErrorMessage = 'OCRをスキップしたため、賞味期限は手動で選択してください。';
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

    // 年リストは「選択値が items に存在しない」事故を避けるため、選択年を必ず含む範囲にする。
    // OCR誤認識で極端な年が出た場合にDropdownが落ちないように、現実的な範囲でガードする。
    final int minPlausibleYear = now.year - 1;
    final int maxPlausibleYear = now.year + 30;

    int startYear = now.year;
    int endYear = now.year + 5;

    if (_selectedYear != null) {
      final y = _selectedYear!;
      // 極端な値は無視（parse側でも弾くが、万一入ってもUIで落とさない）
      if (y >= minPlausibleYear && y <= maxPlausibleYear) {
        startYear = min(startYear, y - 2);
        endYear = max(endYear, y + 2);
      }
    }

    startYear = startYear.clamp(minPlausibleYear, maxPlausibleYear);
    endYear = endYear.clamp(minPlausibleYear, maxPlausibleYear);
    if (startYear > endYear) {
      startYear = now.year;
      endYear = now.year + 5;
      startYear = startYear.clamp(minPlausibleYear, maxPlausibleYear);
      endYear = endYear.clamp(minPlausibleYear, maxPlausibleYear);
    }

    final years = <int>[
      for (int y = startYear; y <= endYear; y++) y,
    ];

    final months = List<int>.generate(12, (i) => i + 1);

    final int baseYear = _selectedYear ?? now.year;
    final int baseMonth = _selectedMonth ?? 1;
    final int maxDay = _daysInMonth(baseYear, baseMonth);
    final days = List<int>.generate(maxDay, (i) => i + 1);

    final String raw = _ocrRawText ?? '';
    final String normalized = _ocrNormalizedForDebug ?? '';
    final String fixed = normalized.isNotEmpty ? _fixDigits(normalized) : '';

    String parsedLabel = 'null';
    if (_ocrParsedForDebug != null) {
      final dt = _ocrParsedForDebug!;
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      parsedLabel = '$y-$m-$d';
    }

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

                    // ===== ここだけ追加：編集画面でOCRデバッグを見えるようにする =====
                    // kDebugMode の時だけ表示（リリースでは出ません）
                    if (kDebugMode && (_ocrRawText != null)) ...[
                      const SizedBox(height: 8),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('OCRデバッグ（開発時のみ）'),
                        subtitle: Text(
                          (_ocrRawText?.trim().isNotEmpty ?? false)
                              ? '認識文字列を確認できます'
                              : '認識文字列が空です（点線等で未検出の可能性）',
                        ),
                        children: [
                          _debugBlock(
                            context: context,
                            label: 'Raw（加工なし）',
                            value: raw.isNotEmpty ? raw : '(empty)',
                          ),
                          const SizedBox(height: 8),
                          _debugBlock(
                            context: context,
                            label: 'Normalized（パース用正規化）',
                            value: normalized.isNotEmpty ? normalized : '(empty)',
                          ),
                          const SizedBox(height: 8),
                          _debugBlock(
                            context: context,
                            label: 'Fixed（誤認識補正後・パース用）',
                            value: fixed.isNotEmpty ? fixed : '(empty)',
                          ),
                          const SizedBox(height: 8),
                          _debugBlock(
                            context: context,
                            label: 'Parsed（最終パース結果）',
                            value: parsedLabel,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
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
                            initialValue:
                            _selectedYear != null && years.contains(_selectedYear) ? _selectedYear : null,
                            onChanged: (value) {
                              setState(() {
                                _selectedYear = value;
                                if (_selectedMonth != null && _selectedDay != null) {
                                  final newMaxDay = _daysInMonth(_selectedYear!, _selectedMonth!);
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
                                if (_selectedYear != null && _selectedDay != null) {
                                  final newMaxDay = _daysInMonth(_selectedYear!, _selectedMonth!);
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
                            initialValue: _selectedDay != null && _selectedDay! <= maxDay ? _selectedDay : null,
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
                        onPressed: () => _onTapSelectDateWithCalendar(context),
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

  Widget _debugBlock({
    required BuildContext context,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surfaceVariant,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  // カレンダーから日付を選択
  Future<void> _onTapSelectDateWithCalendar(BuildContext context) async {
    final now = DateTime.now();
    final initial = _buildSelectedExpiry() ?? DateTime(now.year, now.month, now.day);
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

        // デバッグ
        _ocrNormalizedForDebug = null;
        _ocrParsedForDebug = null;
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
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final String text = recognizedText.text;

      // デバッグ用に正規化テキストも保存（表示はkDebugModeのときだけ）
      final normalizedForDebug = _normalizeOcrTextForParse(text);
      final DateTime? parsed = _tryParseExpiryFromText(text);

      setState(() {
        _isRunningOcr = false;
        _ocrRawText = text;

        // デバッグ
        _ocrNormalizedForDebug = normalizedForDebug;
        _ocrParsedForDebug = parsed;

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
  // なるべく多くのケースを拾うための方針:
  // - OCR表示用テキスト(_ocrRawText)は一切加工しない（デバッグに必要）
  // - パース用だけ別に正規化し、誤認識文字を数字に補正する
  //
  // 対応強化:
  // - "2026 / 1/ 30" のような空白混入
  // - "2026 4" / "Z026, 4" のように区切りが消える・誤認識するケース（年月のみ→月末扱い）
  // - 1 が I/l、2 が Z、0 が O になる等の誤認識をパース時のみ補正
  DateTime? _tryParseExpiryFromText(String text) {
    final now = DateTime.now();

    // まず正規化（区切りは空白へ、数字と英字と空白を残す）
    final normalized = _normalizeOcrTextForParse(text);

    // 誤認識補正（パース用だけ）
    final fixed = _fixDigits(normalized);

    final candidates = <DateTime>[];

    // 1) 連続8桁: YYYYMMDD
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

    // 2) 連続6桁: YYMMDD → 20YY
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

    // 3) 空白区切り: YYYY M D（"2026 / 1/ 30" → "2026 1 30"）
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

    // 4) 空白区切り: YY M D → 20YY
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

    // 5) 年月だけ（YYYY M）→ 月末扱い（"2026 4" / "Z026, 4" → "2026 4"）
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

    // 6) 年月だけ（YY M）→ 20YY + 月末
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

    // 複数候補がある場合、"今に近い将来" を優先（ただし過去も近ければ拾う）
    candidates.sort((a, b) => _expiryScore(a, now).compareTo(_expiryScore(b, now)));
    return candidates.first;
  }

  String _normalizeOcrTextForParse(String text) {
    // 年/月/日 などの日本語表記も混ざるので空白へ
    // 区切り候補（/ . - , 全角）も空白へ
    // 数字・英字・空白のみ残して、それ以外は空白へ（Zなどを消さない）
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
    // パース用だけ誤認識を数字に寄せる（表示用テキストはそのまま）
    // 例: Z026 → 2026, I/ l → 1, O → 0
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
    // 駄菓子の賞味期限は多くが近〜中期（とはいえ例外もある）なので、
    // 極端に遠い/古すぎるものは誤認識の可能性が高いとして弾く。
    // - 過去: 10年より古いのは基本ありえない
    // - 未来: 30年より先は基本ありえない
    final min = DateTime(now.year - 10, 1, 1);
    final max = DateTime(now.year + 30, 12, 31);
    return !dt.isBefore(min) && !dt.isAfter(max);
  }

  int _expiryScore(DateTime dt, DateTime now) {
    // 将来の近い日付を優先しつつ、過去でも近ければ次点にする。
    final diffDays = dt.difference(now).inDays;
    if (diffDays >= 0) {
      return diffDays;
    }
    // 過去は少しペナルティを付ける（期限切れ商品もあり得るので完全排除しない）
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

  /// 与えられた [year], [month] の月末日（28〜31 のいずれか）を返す。
  int _lastDayOfMonth(int year, int month) {
    final lastDate = DateTime(year, month + 1, 0);
    return lastDate.day;
  }

  int _daysInMonth(int year, int month) {
    return _lastDayOfMonth(year, month);
  }
}
