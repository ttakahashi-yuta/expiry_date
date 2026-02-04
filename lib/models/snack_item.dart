import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 駄菓子（商品）データを表すモデルクラス。
@immutable
class SnackItem {
  final String? id;
  final String name;
  final DateTime expiry;
  final String? janCode;
  final int? price;

  // ★追加：管理用フィールド
  final bool isArchived;
  final DateTime? createdAt;
  final String? createdByUserId;
  final DateTime? updatedAt;
  final String? updatedByUserId;

  const SnackItem({
    this.id,
    required this.name,
    required this.expiry,
    this.janCode,
    this.price,
    this.isArchived = false,
    this.createdAt,
    this.createdByUserId,
    this.updatedAt,
    this.updatedByUserId,
  });

  SnackItem copyWith({
    String? id,
    String? name,
    DateTime? expiry,
    String? janCode,
    int? price,
    bool? isArchived,
    DateTime? createdAt,
    String? createdByUserId,
    DateTime? updatedAt,
    String? updatedByUserId,
  }) {
    return SnackItem(
      id: id ?? this.id,
      name: name ?? this.name,
      expiry: expiry ?? this.expiry,
      janCode: janCode ?? this.janCode,
      price: price ?? this.price,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByUserId: updatedByUserId ?? this.updatedByUserId,
    );
  }

  /// Firestore 保存用の Map
  /// serverTimestamp() は Repository 側で付与するため、ここでは DateTime を扱う
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'expiry': Timestamp.fromDate(expiry),
      'janCode': janCode,
      'price': price,
      'isArchived': isArchived,
      // 日時系は Repository 側で FieldValue.serverTimestamp() を使うため省略可
    };
  }

  factory SnackItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime? toDateTime(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    return SnackItem(
      id: doc.id,
      name: data['name'] as String? ?? '',
      expiry: toDateTime(data['expiry']) ?? DateTime.now(),
      janCode: data['janCode'] as String?,
      price: (data['price'] as num?)?.toInt(),
      isArchived: data['isArchived'] as bool? ?? false,
      createdAt: toDateTime(data['createdAt']),
      createdByUserId: data['createdByUserId'] as String?,
      updatedAt: toDateTime(data['updatedAt']),
      updatedByUserId: data['updatedByUserId'] as String?,
    );
  }
}