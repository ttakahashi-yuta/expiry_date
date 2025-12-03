import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 駄菓子（商品）データを表すモデルクラス。
/// UI・データ保存の両方で共通して使える。
@immutable
class SnackItem {
  /// Firestore のドキュメントID（まだ保存していない場合やダミーデータでは null）
  final String? id;

  /// 商品名（例：うまい棒 めんたい味）
  final String name;

  /// 賞味期限
  final DateTime expiry;

  /// JANコード（バーコードから取得したコード。まだ未取得なら null）
  final String? janCode;

  /// 売価（税抜 or 税込などは別途扱う想定。未設定なら null）
  final int? price;

  const SnackItem({
    this.id,
    required this.name,
    required this.expiry,
    this.janCode,
    this.price,
  });

  /// 将来の更新処理のための copyWith
  SnackItem copyWith({
    String? id,
    String? name,
    DateTime? expiry,
    String? janCode,
    int? price,
  }) {
    return SnackItem(
      id: id ?? this.id,
      name: name ?? this.name,
      expiry: expiry ?? this.expiry,
      janCode: janCode ?? this.janCode,
      price: price ?? this.price,
    );
  }

  /// Firestore へ保存するための Map 変換
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'expiry': Timestamp.fromDate(expiry),
      'janCode': janCode,
      'price': price,
    };
  }

  /// Firestore から取得した DocumentSnapshot から SnackItem を生成
  factory SnackItem.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Missing data for SnackItem document: ${doc.id}');
    }

    final expiryField = data['expiry'];
    DateTime expiry;
    if (expiryField is Timestamp) {
      expiry = expiryField.toDate();
    } else if (expiryField is DateTime) {
      expiry = expiryField;
    } else {
      // 想定外の形式だった場合は現在日時でフォールバック
      expiry = DateTime.now();
    }

    final dynamic priceRaw = data['price'];
    int? price;
    if (priceRaw is int) {
      price = priceRaw;
    } else if (priceRaw is num) {
      price = priceRaw.toInt();
    }

    return SnackItem(
      id: doc.id,
      name: data['name'] as String? ?? '',
      expiry: expiry,
      janCode: data['janCode'] as String?,
      price: price,
    );
  }
}
