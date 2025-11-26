import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// FirebaseAuth を使った認証まわりの処理をまとめるリポジトリ。
class AuthRepository {
  AuthRepository(this._auth);

  final FirebaseAuth _auth;

  /// 認証状態のストリーム（ログイン／ログアウトを監視）
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Google アカウントでサインイン。
  ///
  /// 成功時は UserCredential を返す。
  Future<UserCredential?> signInWithGoogle() async {
    final googleProvider = GoogleAuthProvider();

    // 必要ならここでスコープやカスタムパラメータを追加できる
    // googleProvider.addScope('https://www.googleapis.com/auth/userinfo.email');
    // googleProvider.setCustomParameters({'prompt': 'select_account'});

    final userCredential = await _auth.signInWithProvider(googleProvider);
    return userCredential;
  }

  /// ログアウト
  Future<void> signOut() async {
    await _auth.signOut();
  }
}

/// AuthRepository を提供する Provider。
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(FirebaseAuth.instance);
});

/// 認証状態 (User? の Stream) を監視する Provider。
final authStateChangesProvider = StreamProvider<User?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges();
});
