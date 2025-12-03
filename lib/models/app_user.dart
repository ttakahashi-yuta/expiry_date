import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Firebase Auth のユーザーに対応するアプリ内ユーザーモデル。
///
/// Firestore 上では `users/{uid}` ドキュメントとして保存される想定。
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

  /// Firebase Auth の UID。
  ///
  /// Firestore 上の `users/{uid}` のドキュメントIDと一致させる。
  final String uid;

  /// 現在、このユーザーが所属している（操作対象の）ショップID。
  ///
  /// - 既存ユーザー: `default-shop` などの文字列が入っている場合がある
  /// - 新規ユーザー: まだショップ未選択の状態を `null` で表現する
  final String? currentShopId;

  /// 表示名（任意）。
  ///
  /// FirebaseAuth の `displayName` を初期値として入れておき、
  /// 必要に応じてアプリ内で変更できるようにすることもできる。
  final String? displayName;

  /// メールアドレス（任意）。
  ///
  /// FirebaseAuth の `email` をそのままコピーしておく。
  final String? email;

  /// 作成日時（サーバー側で付与）。
  ///
  /// Firestore 上では `Timestamp` で保存される。
  final DateTime? createdAt;

  /// 更新日時（サーバー側で付与）。
  ///
  /// Firestore 上では `Timestamp` で保存される。
  final DateTime? updatedAt;

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

  /// Firestore へ保存するためのマップ表現。
  ///
  /// createdAt / updatedAt については、呼び出し側で
  /// `FieldValue.serverTimestamp()` を設定する前提とする。
  Map<String, Object?> toFirestore() {
    return <String, Object?>{
      'currentShopId': currentShopId,
      'displayName': displayName,
      'email': email,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  /// Firestore のドキュメントから AppUser を復元する。
  factory AppUser.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};

    DateTime? toDateTime(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      }
      return null;
    }

    return AppUser(
      uid: doc.id,
      // 既存データに currentShopId があればその値を使い、
      // 無ければ「ショップ未選択」として null のまま扱う。
      currentShopId: data['currentShopId'] as String?,
      displayName: data['displayName'] as String?,
      email: data['email'] as String?,
      createdAt: toDateTime(data['createdAt']),
      updatedAt: toDateTime(data['updatedAt']),
    );
  }
}
