import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expiry_date/models/snack_item.dart';
import 'package:expiry_date/core/user/user_providers.dart';

/// Firestore 上の「在庫（snacks）」を扱うリポジトリ。
///
/// コレクション構造（案）:
/// shops/{shopId}/snacks/{snackId}
class SnackRepository {
  SnackRepository(
      this._firestore, {
        required this.shopId,
      });

  final FirebaseFirestore _firestore;

  /// このユーザーが現在操作している「店」のID。
  /// とりあえずは固定文字列や、将来は設定画面から変更できるようにする。
  final String shopId;

  /// shops/{shopId}/snacks コレクション
  CollectionReference<Map<String, dynamic>> get _snacksCol =>
      _firestore.collection('shops').doc(shopId).collection('snacks');

  /// 在庫一覧を監視（賞味期限順）。
  Stream<List<SnackItem>> watchSnacks() {
    return _snacksCol
        .orderBy('expiry')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map((doc) => SnackItem.fromFirestore(doc))
          .toList(),
    );
  }

  /// 新しい在庫を追加。
  ///
  /// 追加後、ドキュメントIDが入った SnackItem を返す。
  Future<SnackItem> addSnack(SnackItem snack) async {
    final docRef = await _snacksCol.add(snack.toFirestore());
    final docSnap = await docRef.get();
    return SnackItem.fromFirestore(docSnap);
  }

  /// 既存在庫を更新。
  Future<void> updateSnack(SnackItem snack) async {
    final id = snack.id;
    if (id == null) {
      throw StateError('updateSnack called with SnackItem that has no id.');
    }
    await _snacksCol.doc(id).update(snack.toFirestore());
  }

  /// 在庫を削除。
  Future<void> deleteSnack(String id) async {
    await _snacksCol.doc(id).delete();
  }
}

/// SnackRepository 自体を提供する Provider。
final snackRepositoryProvider = Provider<SnackRepository>((ref) {
  final firestore = FirebaseFirestore.instance;
  final shopId = ref.watch(shopIdProvider);
  return SnackRepository(
    firestore,
    shopId: shopId,
  );
});

/// Firestore 上の在庫一覧を監視する StreamProvider。
///
/// 次のステップで HomeScreen からこれを watch するように差し替えていく。
final snackListStreamProvider = StreamProvider<List<SnackItem>>((ref) {
  final repo = ref.watch(snackRepositoryProvider);
  return repo.watchSnacks();
});
