import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:expiry_date/models/app_user.dart';

/// Firestore 上の `users/{uid}` ドキュメントを扱うリポジトリ。
class UserRepository {
  UserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection('users');

  /// ユーザードキュメントを確実に作成・更新し、最新の状態を返す。
  /// 書き込み後の再読み取りを省き、通信コストを最適化。
  Future<AppUser> ensureUserDocument(User firebaseUser) async {
    final docRef = _usersRef.doc(firebaseUser.uid);
    final snapshot = await docRef.get();

    if (snapshot.exists) {
      // 既存ユーザーの処理
      final existing = AppUser.fromFirestore(snapshot);

      final String? newDisplayName = firebaseUser.displayName;
      final String? newEmail = firebaseUser.email;

      final Map<String, Object?> updates = <String, Object?>{};

      if (newDisplayName != null &&
          newDisplayName.trim().isNotEmpty &&
          newDisplayName != existing.displayName) {
        updates['displayName'] = newDisplayName;
      }

      if (newEmail != null &&
          newEmail.trim().isNotEmpty &&
          newEmail != existing.email) {
        updates['email'] = newEmail;
      }

      if (updates.isNotEmpty) {
        updates['updatedAt'] = FieldValue.serverTimestamp();
        await docRef.update(updates);

        // ★改善：再読み取り(get)をせず、手元のデータで更新後のオブジェクトを作る
        return existing.copyWith(
          displayName: newDisplayName ?? existing.displayName,
          email: newEmail ?? existing.email,
        );
      }

      return existing;
    }

    // 新規ユーザーの作成
    final Map<String, dynamic> newData = {
      'displayName': firebaseUser.displayName,
      'email': firebaseUser.email,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      // currentShopId は初期状態では含めない（null扱い）
    };

    await docRef.set(newData);

    // ★改善：setした直後のデータをそのままAppUserにして返す（Readコストを削減）
    return AppUser(
      uid: firebaseUser.uid,
      displayName: firebaseUser.displayName,
      email: firebaseUser.email,
      currentShopId: null,
    );
  }

  /// 単発でユーザー情報を取得する。
  Future<AppUser?> fetchUser(String uid) async {
    final docRef = _usersRef.doc(uid);
    final snapshot = await docRef.get();
    if (!snapshot.exists) return null;
    return AppUser.fromFirestore(snapshot);
  }

  /// Firestore 上のユーザードキュメントを監視するストリーム。
  Stream<AppUser?> watchUser(String uid) {
    final docRef = _usersRef.doc(uid);
    return docRef.snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return AppUser.fromFirestore(snapshot);
    });
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(FirebaseFirestore.instance);
});