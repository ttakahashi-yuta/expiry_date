import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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

  /// Apple ID でサインイン。
  ///
  /// iOS の App Store 審査要件（サードパーティログインを提供する場合）に対応するために追加。
  /// 成功時は UserCredential を返す。
  ///
  /// ※ユーザーがキャンセルした場合は null を返す。
  Future<UserCredential?> signInWithApple() async {
    // Apple Sign-In は nonce 付きで行うのが推奨（リプレイ攻撃対策）
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    try {
      final appleIdCredential = await SignInWithApple.getAppleIDCredential(
        scopes: <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final idToken = appleIdCredential.identityToken;
      final authorizationCode = appleIdCredential.authorizationCode;

      if (idToken == null || idToken.isEmpty) {
        throw StateError('AppleのidentityTokenを取得できませんでした。');
      }

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: idToken,
        accessToken: authorizationCode,
        rawNonce: rawNonce,
      );

      final userCredential = await _auth.signInWithCredential(oauthCredential);
      return userCredential;
    } on SignInWithAppleAuthorizationException catch (e) {
      // ユーザーがキャンセルした場合は null 扱い
      if (e.code == AuthorizationErrorCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  /// ログアウト
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// ランダムnonceを生成（Firebase推奨パターン）
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    final chars = List<String>.generate(
      length,
          (_) => charset[random.nextInt(charset.length)],
    );
    return chars.join();
  }

  /// SHA256ハッシュ
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
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
