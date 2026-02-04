import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expiry_date/models/snack_item.dart';
import 'package:expiry_date/core/user/user_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firestore 上の「在庫（snacks）」を扱うリポジトリ。
class SnackRepository {
  SnackRepository(this._firestore, {required this.shopId});

  final FirebaseFirestore _firestore;

  /// 現在操作中のショップID
  final String shopId;

  /// shops/{shopId}/snacks コレクションへの参照
  CollectionReference<Map<String, dynamic>> get _snacksCol =>
      _firestore.collection('shops').doc(shopId).collection('snacks');

  /// 【在庫一覧】を監視（アーカイブされていないもの限定、賞味期限順）
  /// 移行（B案）完了により、Firestore 側で高速にフィルタリング可能です。
  Stream<List<SnackItem>> watchSnacks() {
    return _snacksCol
        .where('isArchived', isEqualTo: false) // ★サーバー側フィルタ
        .orderBy('expiry') // ★賞味期限順
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => SnackItem.fromFirestore(doc)).toList());
  }

  /// 【ゴミ箱】の一覧を監視
  Stream<List<SnackItem>> watchArchivedSnacks() {
    return _snacksCol
        .where('isArchived', isEqualTo: true)
        .orderBy('expiry')
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => SnackItem.fromFirestore(doc)).toList());
  }

  /// 新しい在庫を追加。
  /// 追加後の再取得（Read）を省略し、コストを最適化しています。
  Future<SnackItem> addSnack(SnackItem snack) async {
    final user = FirebaseAuth.instance.currentUser;
    final Map<String, dynamic> data = snack.toFirestore();

    // メタデータの自動付与
    data['isArchived'] = false;
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['createdByUserId'] = user?.uid;
    data['updatedByUserId'] = user?.uid;

    final docRef = await _snacksCol.add(data);

    // 生成されたIDをセットして返し、呼び出し側での再読み込みを不要にします
    return snack.copyWith(
      id: docRef.id,
      isArchived: false,
    );
  }

  /// 既存在庫の更新
  Future<void> updateSnack(SnackItem snack) async {
    if (snack.id == null) return;
    final user = FirebaseAuth.instance.currentUser;
    final data = snack.toFirestore();

    data['updatedAt'] = FieldValue.serverTimestamp();
    data['updatedByUserId'] = user?.uid;

    await _snacksCol.doc(snack.id).update(data);
  }

  /// ゴミ箱に移動（論理削除）
  Future<void> archiveSnack(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    await _snacksCol.doc(id).update({
      'isArchived': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUserId': user?.uid,
      'archivedAt': FieldValue.serverTimestamp(),
      'archivedByUserId': user?.uid,
    });
  }

  /// ゴミ箱から復元
  Future<void> restoreSnack(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    await _snacksCol.doc(id).update({
      'isArchived': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUserId': user?.uid,
      'archivedAt': null,
      'archivedByUserId': null,
    });
  }

  /// 物理削除（ゴミ箱からも完全に消去）
  Future<void> deleteSnackPermanently(String id) async {
    await _snacksCol.doc(id).delete();
  }
}

/// Provider 定義
final snackRepositoryProvider = Provider<SnackRepository>((ref) {
  // main.dart の currentShopIdProvider を監視
  final shopId = ref.watch(currentShopIdProvider);
  return SnackRepository(FirebaseFirestore.instance, shopId: shopId);
});

/// 在庫一覧を監視する StreamProvider
final snackListStreamProvider = StreamProvider<List<SnackItem>>((ref) {
  final repo = ref.watch(snackRepositoryProvider);
  return repo.watchSnacks();
});

/// アーカイブ（ゴミ箱）一覧を監視する StreamProvider
final archivedSnackListStreamProvider = StreamProvider<List<SnackItem>>((ref) {
  final repo = ref.watch(snackRepositoryProvider);
  return repo.watchArchivedSnacks();
});