import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:expiry_date/core/auth/auth_repository.dart';
import 'package:expiry_date/core/shop/shop_config.dart';
import 'package:expiry_date/core/user/user_repository.dart';
import 'package:expiry_date/models/app_user.dart';

/// 認証状態と Firestore 上の users/{uid} をつないで
/// AppUser? のストリームとして提供する Provider。
///
/// - 未ログイン: data は null
/// - ログイン済み:
///   - 必要に応じて users/{uid} を作成したうえで
///   - そのドキュメントを watch し続ける
final appUserStreamProvider = StreamProvider<AppUser?>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final userRepo = ref.watch(userRepositoryProvider);

  // FirebaseAuth の状態変化を起点に、対応するユーザードキュメントを監視する。
  return authRepo.authStateChanges().asyncExpand((firebaseUser) async* {
    if (firebaseUser == null) {
      // ログアウト時などは null を流す。
      yield null;
      return;
    }

    // users/{uid} が存在しない場合は作成しておく。
    await userRepo.ensureUserDocument(firebaseUser);

    // その後は users/{uid} のスナップショットを監視する。
    yield* userRepo.watchUser(firebaseUser.uid).where((_) => true);
  });
});

/// 現在のユーザーが所属している shopId を返す Provider。
///
/// - ログイン済みで AppUser が取得できていれば、その currentShopId
/// - ローディング中／エラー／未ログイン時は kDefaultShopId
final currentShopIdProvider = Provider<String>((ref) {
  final appUserAsync = ref.watch(appUserStreamProvider);

  return appUserAsync.when(
    data: (appUser) => appUser?.currentShopId ?? kDefaultShopId,
    loading: () => kDefaultShopId,
    error: (_, __) => kDefaultShopId,
  );
});

/// 既存コードとの互換性のためのエイリアス Provider。
///
/// 今後は currentShopIdProvider を直接使うことを推奨するが、
/// すでに shopIdProvider を参照しているコードからも利用できるようにしておく。
final shopIdProvider = Provider<String>((ref) {
  return ref.watch(currentShopIdProvider);
});
