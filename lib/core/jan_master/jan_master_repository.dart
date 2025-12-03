// lib/core/jan_master/jan_master_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:expiry_date/core/shop/shop_config.dart';
import 'package:expiry_date/core/user/user_providers.dart';

/// Firestore 上の「JAN コードごとのマスタ情報」を表すエントリ。
class JanMasterEntry {
  JanMasterEntry({
    required this.janCode,
    required this.name,
    this.price,
    this.updatedAt,
    this.updatedByUserId,
  });

  /// ドキュメントID（JANコード）
  final String janCode;

  /// 商品名（最後に入力されたもの）
  final String name;

  /// 売価（最後に入力されたもの）
  final int? price;

  /// 最終更新日時
  final DateTime? updatedAt;

  /// 最終更新を行ったユーザーID
  final String? updatedByUserId;

  factory JanMasterEntry.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('JANマスタのデータが存在しません: ${doc.id}');
    }

    return JanMasterEntry(
      janCode: doc.id,
      name: data['name'] as String? ?? '',
      price: (data['price'] as num?)?.toInt(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      updatedByUserId: data['updatedByUserId'] as String?,
    );
  }
}

/// `shops/{shopId}/janMaster/{janCode}` を扱うリポジトリ。
class JanMasterRepository {
  JanMasterRepository(
      this._db, {
        this.shopId = kDefaultShopId,
      });

  final FirebaseFirestore _db;

  /// このリポジトリが操作対象とするショップID。
  ///
  /// デフォルト値として kDefaultShopId を残してあるが、
  /// 実際の運用では janMasterRepositoryProvider から
  /// currentShopIdProvider / shopIdProvider 経由で渡される。
  final String shopId;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection('shops').doc(shopId).collection('janMaster');

  /// JANコードに対応するマスタ情報を1件取得（なければ null）。
  Future<JanMasterEntry?> fetchJan(String janCode) async {
    final doc = await _collection.doc(janCode).get();
    if (!doc.exists) {
      return null;
    }
    return JanMasterEntry.fromDoc(doc);
  }

  /// JANコードに紐づく名前・売価を「最後の入力値」として保存する。
  ///
  /// 既存ドキュメントがあれば merge 更新、なければ作成。
  Future<void> upsertJan({
    required String janCode,
    required String name,
    int? price,
    required String userId,
  }) async {
    await _collection.doc(janCode).set(
      <String, dynamic>{
        'name': name,
        'price': price,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUserId': userId,
      },
      SetOptions(merge: true),
    );
  }
}

/// JanMasterRepository を提供する Provider。
///
/// 現在のユーザーが所属している shopId（currentShopIdProvider）を参照して、
/// そのショップ配下の `janMaster` コレクションを操作する。
final janMasterRepositoryProvider = Provider<JanMasterRepository>((ref) {
  final db = FirebaseFirestore.instance;
  final shopId = ref.watch(shopIdProvider);
  return JanMasterRepository(
    db,
    shopId: shopId,
  );
});
