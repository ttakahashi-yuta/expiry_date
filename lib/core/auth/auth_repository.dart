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
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final googleProvider = GoogleAuthProvider();
      // 2026年現在の推奨メソッドを使用
      return await _auth.signInWithProvider(googleProvider);
    } on FirebaseAuthException catch (e) {
      // ユーザーが選択画面を閉じた場合などは null を返して安全に終了させる
      if (e.code == 'closed-by-user' || e.code == 'canceled') {
        return null;
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  /// Apple ID でサインイン。
  Future<UserCredential?> signInWithApple() async {
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

      return await _auth.signInWithCredential(oauthCredential);
    } on SignInWithAppleAuthorizationException catch (e) {
      // ユーザーキャンセル時は null 扱い
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

  /// ランダムnonceを生成
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List<String>.generate(
      length,
          (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// SHA256ハッシュ
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(FirebaseAuth.instance);
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});