import 'package:flutter/foundation.dart';

/// 駄菓子（商品）データを表すモデルクラス。
/// UI・データ保存の両方で共通して使える。
@immutable
class SnackItem {
  /// 商品名（例：うまい棒 めんたい味）
  final String name;

  /// 賞味期限
  final DateTime expiry;

  /// JANコード（バーコードから取得したコード。まだ未取得なら null）
  final String? janCode;

  /// 売価（税抜 or 税込などは別途扱う想定。未設定なら null）
  final int? price;

  const SnackItem({
    required this.name,
    required this.expiry,
    this.janCode,
    this.price,
  });

  /// 将来の更新処理のための copyWith
  SnackItem copyWith({
    String? name,
    DateTime? expiry,
    String? janCode,
    int? price,
  }) {
    return SnackItem(
      name: name ?? this.name,
      expiry: expiry ?? this.expiry,
      janCode: janCode ?? this.janCode,
      price: price ?? this.price,
    );
  }
}
