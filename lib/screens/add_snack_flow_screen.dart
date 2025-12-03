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
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  final ImagePicker _picker = ImagePicker();
  bool _isRunningOcr = false;
  String? _ocrRawText;
  String? _ocrErrorMessage;
  XFile? _expiryImage;

  @override
  void dispose() {
    _nameController.dispose();
    _expiryController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(
                color:
                Theme.of(context).colorScheme.onSurfaceVariant),
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
          FilledButton(
            onPressed: (_expiryImage == null || _isRunningOcr)
                ? null
                : () {
              setState(() {
                _step = AddSnackStep.editDetails;
              });
            },
            child: const Text('この結果で次へ'),
          ),
          TextButton(
            onPressed: _isRunningOcr
                ? null
                : () {
              setState(() {
                _step = AddSnackStep.editDetails;
                _ocrErrorMessage =
                'OCRをスキップしたため、賞味期限は手入力してください。';
              });
            },
            child: const Text('OCRを使わずに手入力する'),
          ),
        ],
      ),
    );
  }

  // 3. 商品名／賞味期限／売価の入力ステップ
  Widget _buildEditDetailsStep(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('edit_details'),
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _expiryController,
              decoration: InputDecoration(
                labelText: '賞味期限',
                hintText: '例）2025/12/31',
                helperText: _ocrErrorMessage ??
                    'OCR結果を元に自動入力されています。必要に応じて修正してください。',
              ),
              keyboardType: TextInputType.datetime,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '賞味期限を入力してください';
                }
                if (_parseExpiryFromField(value) == null) {
                  return '日付の形式が正しくありません（例：2025/12/31）';
                }
                return null;
              },
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
          ],
        ),
      ),
    );
  }

  // 賞味期限撮影＋OCRの実装
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
          _expiryController.text = _formatDate(parsed);
          _ocrErrorMessage = null;
        } else {
          _ocrErrorMessage =
          '賞味期限の日付を自動で特定できませんでした。テキストを参考に手入力してください。';
        }
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
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final DateTime? expiry = _parseExpiryFromField(_expiryController.text);
    if (expiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('賞味期限の日付形式を確認してください。')),
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

  DateTime? _parseExpiryFromField(String? text) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    return _tryParseExpiryFromText(text);
  }

  // OCR結果のテキストから日付っぽい部分を抜き出してDateTimeにする
  DateTime? _tryParseExpiryFromText(String text) {
    final normalized = text
        .replaceAll('年', '/')
        .replaceAll('月', '/')
        .replaceAll('日', '')
        .replaceAll(RegExp(r'[^0-9/.\-]'), ' ');

    // 例：2025/12/31, 2025-12-31, 2025.12.31
    final match4 =
    RegExp(r'(\d{4})[./\-](\d{1,2})[./\-](\d{1,2})').firstMatch(normalized);
    if (match4 != null) {
      final year = int.parse(match4.group(1)!);
      final month = int.parse(match4.group(2)!);
      final day = int.parse(match4.group(3)!);
      if (_isValidYmd(year, month, day)) {
        return DateTime(year, month, day);
      }
    }

    // 例：25/12/31, 25-12-31 など（西暦下2桁扱いで 2000+xx とみなす）
    final match2 =
    RegExp(r'(\d{2})[./\-](\d{1,2})[./\-](\d{1,2})').firstMatch(normalized);
    if (match2 != null) {
      final twoDigitYear = int.parse(match2.group(1)!);
      final year = 2000 + twoDigitYear;
      final month = int.parse(match2.group(2)!);
      final day = int.parse(match2.group(3)!);
      if (_isValidYmd(year, month, day)) {
        return DateTime(year, month, day);
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

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }
}
