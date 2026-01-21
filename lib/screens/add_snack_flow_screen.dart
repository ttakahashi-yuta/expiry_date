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

  // ===== JANマスタ取得結果（SnackBarではなく画面上に表示する）=====
  bool _isLoadingJanMaster = false;
  String? _janMasterErrorMessage;
  String? _masterName;
  int? _masterPrice;

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

  void _resetForRescan() {
    setState(() {
      _step = AddSnackStep.scanBarcode;
      _isScanningBarcode = true;

      _janCode = null;

      // 期限撮影/OCR周り
      _isRunningOcr = false;
      _ocrRawText = null;
      _ocrErrorMessage = null;
      _expiryImage = null;

      // デバッグ
      _ocrNormalizedForDebug = null;
      _ocrParsedForDebug = null;

      // マスタ取得周り
      _isLoadingJanMaster = false;
      _janMasterErrorMessage = null;
      _masterName = null;
      _masterPrice = null;

      // 入力値（JANから再スタートなので一旦クリア）
      _nameController.text = '';
      _priceController.text = '';

      // 期限選択もクリア
      _selectedYear = null;
      _selectedMonth = null;
      _selectedDay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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

                // 直前の状態をクリア（再スキャン等の混線防止）
                _janMasterErrorMessage = null;
                _masterName = null;
                _masterPrice = null;
              });

              // Firestore 上の JAN マスタから、商品名・売価を取得（SnackBarは出さない）
              _loadJanMasterForJanCode(rawValue);
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

                    // マスタも無し
                    _isLoadingJanMaster = false;
                    _janMasterErrorMessage = null;
                    _masterName = null;
                    _masterPrice = null;
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
  // - JANコードがマスタ登録済みなら、この画面で商品名・売価を表示する
  // - 「バーコードをもう一度スキャンする」ボタンで最初に戻れる
  Widget _buildCaptureExpiryStep(BuildContext context) {
    final hasJan = _janCode != null && _janCode!.trim().isNotEmpty;
    final hasMaster = (_masterName != null && _masterName!.trim().isNotEmpty) || (_masterPrice != null);

    final valueNameStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final valuePriceStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );

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
          const SizedBox(height: 12),
          if (hasJan) ...[
            Text(
              'JANコード',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(
              _janCode!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
          ],

          // ===== マスタ取得結果（画面表示）=====
          if (hasJan) ...[
            if (_isLoadingJanMaster) ...[
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'マスタから商品情報を取得しています…',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ] else if (_janMasterErrorMessage != null) ...[
              Text(
                _janMasterErrorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
            ] else if (hasMaster) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'マスタから取得した商品情報',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '商品名',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (_masterName != null && _masterName!.trim().isNotEmpty) ? _masterName! : '（未登録）',
                      style: valueNameStyle,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '売価',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _masterPrice != null ? '${_masterPrice!}円' : '（未登録）',
                      style: valuePriceStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],

          // バーコード再スキャン
          if (hasJan) ...[
            OutlinedButton.icon(
              onPressed: _isRunningOcr ? null : _resetForRescan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('バーコードをもう一度スキャンする'),
            ),
            const SizedBox(height: 12),
          ],

          // 撮影済みのときだけ画像を表示する（プレースホルダーは出さない）
          if (_expiryImage != null) ...[
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
            ),
            const SizedBox(height: 16),
          ] else ...[
            const SizedBox(height: 8),
          ],

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
          const SizedBox(height: 16),
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

              // マスタ取得済みなら、編集画面の入力欄へ「空欄の場合のみ」反映しておく
              _applyMasterToControllersIfEmpty();
            },
            child: const Text('OCRを使わずに手入力する'),
          ),
        ],
      ),
    );
  }

  // 3. 商品名／賞味期限／売価の入力ステップ
  //
  // ここだけ変更：指定の要素の文字サイズを少し大きくする
  Widget _buildEditDetailsStep(BuildContext context) {
    final now = DateTime.now();

    // ========= 文字サイズ調整（本体設定のTextScaleFactor制御は今回はしない） =========
    const double _fieldFontSize = 18; // TextFormField の入力文字
    const double _labelFontSize = 16; // TextFormFieldのラベル
    const double _buttonFontSize = 16; // カレンダー/再撮影ボタン
    const double _buttonIconSize = 22;

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

    final inputTextStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: _fieldFontSize,
    );
    final labelTextStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontSize: _labelFontSize,
    );

    final buttonStyle = TextButton.styleFrom(
      textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontSize: _buttonFontSize,
        fontWeight: FontWeight.w600,
      ),
    );

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

                    // 商品名（少し大きく）
                    TextFormField(
                      controller: _nameController,
                      style: inputTextStyle,
                      decoration: InputDecoration(
                        labelText: '商品名',
                        hintText: '例）うまい棒 めんたい味',
                        labelStyle: labelTextStyle,
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
                            decoration: InputDecoration(
                              labelText: '年',
                              labelStyle: labelTextStyle,
                            ),
                            items: years
                                .map(
                                  (y) => DropdownMenuItem<int>(
                                value: y,
                                child: Text(
                                  '$y年',
                                  style: inputTextStyle,
                                ),
                              ),
                            )
                                .toList(),
                            initialValue: _selectedYear != null && years.contains(_selectedYear) ? _selectedYear : null,
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
                            decoration: InputDecoration(
                              labelText: '月',
                              labelStyle: labelTextStyle,
                            ),
                            items: months
                                .map(
                                  (m) => DropdownMenuItem<int>(
                                value: m,
                                child: Text(
                                  '$m月',
                                  style: inputTextStyle,
                                ),
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
                            decoration: InputDecoration(
                              labelText: '日',
                              labelStyle: labelTextStyle,
                            ),
                            items: days
                                .map(
                                  (d) => DropdownMenuItem<int>(
                                value: d,
                                child: Text(
                                  '$d日',
                                  style: inputTextStyle,
                                ),
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

                    // カレンダーから日付を入力ボタン（少し大きく）
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: buttonStyle,
                        onPressed: () => _onTapSelectDateWithCalendar(context),
                        icon: Icon(Icons.calendar_today, size: _buttonIconSize),
                        label: const Text('カレンダーから選択'),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // 賞味期限をもう一度撮影ボタン（少し大きく）
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: buttonStyle,
                        onPressed: _isRunningOcr ? null : _onTapCaptureExpiry,
                        icon: Icon(Icons.camera_alt_outlined, size: _buttonIconSize),
                        label: const Text('賞味期限をもう一度撮影する'),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // 売価（少し大きく）
                    TextFormField(
                      controller: _priceController,
                      style: inputTextStyle,
                      decoration: InputDecoration(
                        labelText: '売価（円）',
                        hintText: '例）30',
                        labelStyle: labelTextStyle,
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
          _ocrErrorMessage = '賞味期限の日付を自動で特定できませんでした。プルダウンまたはカレンダーから選択してください。';
        }
      });

      if (!mounted) return;

      // ここで編集画面に進む前に、マスタ取得済みなら入力欄へ反映しておく（空欄の場合のみ）
      _applyMasterToControllersIfEmpty();

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

  // 「商品を追加」押下時
  Future<void> _onSubmit() async {
    FocusScope.of(context).unfocus();

    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final DateTime? expiry = _buildSelectedExpiry();
    if (expiry == null) {
      setState(() {
        _ocrErrorMessage = '賞味期限を選択してください。';
      });
      return;
    }

    final String name = _nameController.text.trim();
    final String priceText = _priceController.text.trim();
    int? price;

    if (priceText.isNotEmpty) {
      price = int.tryParse(priceText.replaceAll(',', ''));
      if (price == null) {
        setState(() {
          _ocrErrorMessage = '売価には数値を入力してください。';
        });
        return;
      }
    }

    final snack = SnackItem(
      name: name,
      expiry: expiry,
      janCode: _janCode,
      price: price,
    );

    await _updateJanMasterIfNeeded(snack);

    if (!mounted) return;
    Navigator.of(context).pop(snack);
  }

  /// JANコードに対応する JAN マスタ情報を読み込み、
  /// 取得結果は SnackBar ではなく画面上に表示する。
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

  int _lastDayOfMonth(int year, int month) {
    final lastDate = DateTime(year, month + 1, 0);
    return lastDate.day;
  }

  int _daysInMonth(int year, int month) {
    return _lastDayOfMonth(year, month);
  }
}
