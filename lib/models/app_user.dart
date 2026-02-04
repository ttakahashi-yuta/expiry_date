import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Firebase Auth のユーザーに対応するアプリ内ユーザーモデル。
@immutable
class AppUser {
  const AppUser({
    required this.uid,
    this.currentShopId,
    this.displayName,
    this.email,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String? currentShopId;
  final String? displayName;
  final String? email;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 値を一部書き換えた新しいインスタンスを生成する
  AppUser copyWith({
    String? uid,
    String? currentShopId,
    String? displayName,
    String? email,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      currentShopId: currentShopId ?? this.currentShopId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Firestore 保存用のマップ。
  /// createdAt/updatedAt は repository 側で FieldValue.serverTimestamp() を入れるため
  /// ここでは主に基本情報のみを扱う。
  Map<String, Object?> toFirestore() {
    return <String, Object?>{
      'currentShopId': currentShopId,
      'displayName': displayName,
      'email': email,
      // repository側で制御するため、ここには Timestamp を直接入れない運用が安全
    };
  }

  /// Firestore のドキュメントから AppUser を復元する。
  factory AppUser.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};

    DateTime? toDateTime(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return null;
    }

    return AppUser(
      uid: doc.id,
      currentShopId: data['currentShopId'] as String?,
      displayName: data['displayName'] as String?,
      email: data['email'] as String?,
      createdAt: toDateTime(data['createdAt']),
      updatedAt: toDateTime(data['updatedAt']),
    );
  }
}