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

  /// FirebaseAuth の [firebaseUser] に対応するユーザードキュメントを
  /// Firestore 上に必ず作成した上で、その内容を [AppUser] として返す。
  ///
  /// 既に存在する場合はそれを読み込んで返す。
  /// 存在しない場合は新規に作成し、その後のドキュメント内容を返す。
  ///
  /// ※新規作成時には currentShopId は設定せず、
  ///   「ショップ未選択」の状態を null で表現する。
  ///
  /// ※既存ドキュメントがある場合：
  ///   Appleログイン等では displayName/email が null になることがあるため、
  ///   null で上書きしないように注意する。
  Future<AppUser> ensureUserDocument(User firebaseUser) async {
    final docRef = _usersRef.doc(firebaseUser.uid);
    final snapshot = await docRef.get();

    if (snapshot.exists) {
      // 既存ユーザー：nullで上書きしない範囲で、必要なら更新する
      final existing = AppUser.fromFirestore(snapshot);

      final String? newDisplayName = firebaseUser.displayName;
      final String? newEmail = firebaseUser.email;

      final Map<String, Object?> updates = <String, Object?>{};

      // displayName: Auth側が null なら更新しない
      if (newDisplayName != null &&
          newDisplayName.trim().isNotEmpty &&
          newDisplayName != existing.displayName) {
        updates['displayName'] = newDisplayName;
      }

      // email: Auth側が null なら更新しない
      if (newEmail != null &&
          newEmail.trim().isNotEmpty &&
          newEmail != existing.email) {
        updates['email'] = newEmail;
      }

      // 何かしら更新があるときだけ updatedAt を更新する
      if (updates.isNotEmpty) {
        updates['updatedAt'] = FieldValue.serverTimestamp();
        await docRef.update(updates);
        final updatedSnapshot = await docRef.get();
        return AppUser.fromFirestore(updatedSnapshot);
      }

      return existing;
    }

    // 新規ユーザー：displayName/email が null の可能性はあるが、そのまま保存でOK
    await docRef.set(<String, Object?>{
      // currentShopId はあえて書かない（null のまま＝ショップ未選択）
      'displayName': firebaseUser.displayName,
      'email': firebaseUser.email,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final createdSnapshot = await docRef.get();
    return AppUser.fromFirestore(createdSnapshot);
  }

  /// 単発でユーザー情報を取得する。
  ///
  /// ドキュメントが存在しない場合は null を返す。
  Future<AppUser?> fetchUser(String uid) async {
    final docRef = _usersRef.doc(uid);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      return null;
    }
    return AppUser.fromFirestore(snapshot);
  }

  /// Firestore 上のユーザードキュメントを監視するストリーム。
  ///
  /// ドキュメントが存在しない状態では null を返す。
  Stream<AppUser?> watchUser(String uid) {
    final docRef = _usersRef.doc(uid);
    return docRef.snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return AppUser.fromFirestore(snapshot);
    });
  }
}

/// [UserRepository] 自体を提供する Provider。
final userRepositoryProvider = Provider<UserRepository>((ref) {
  final firestore = FirebaseFirestore.instance;
  return UserRepository(firestore);
});
