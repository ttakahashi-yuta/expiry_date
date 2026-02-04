import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ショップ関連（メンバー判定 / 招待QR発行 / QR受諾 / 売価設定）を扱うリポジトリ。
class ShopRepository {
  ShopRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const Duration inviteTtl = Duration(hours: 24);

  CollectionReference<Map<String, dynamic>> get _shopsRef =>
      _firestore.collection('shops');

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection('users');

  /// 現在ログインしているユーザーUIDを返す（未ログインならnull）
  String? get currentUid => _auth.currentUser?.uid;

  /// shops/{shopId} を取得
  Future<ShopInfo?> fetchShopInfo(String shopId) async {
    final snap = await _shopsRef.doc(shopId).get();
    if (!snap.exists) return null;

    final data = snap.data() ?? <String, dynamic>{};
    final name = data['name'] as String? ?? '';
    final ownerUserId = data['ownerUserId'] as String?;

    return ShopInfo(
      shopId: snap.id,
      name: name,
      ownerUserId: ownerUserId,
    );
  }

  /// shops/{shopId}/members/{uid} を監視
  Stream<ShopMember?> watchMyMembership(String shopId) {
    final uid = currentUid;
    if (uid == null) {
      return Stream<ShopMember?>.value(null);
    }

    final docRef = _shopsRef.doc(shopId).collection('members').doc(uid);
    return docRef.snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data() ?? <String, dynamic>{};
      final role = data['role'] as String?;
      final joinedAt = _toDateTime(data['joinedAt']);
      final addedByUserId = data['addedByUserId'] as String?;
      return ShopMember(
        uid: uid,
        role: role ?? 'member',
        joinedAt: joinedAt,
        addedByUserId: addedByUserId,
      );
    });
  }

  /// 現在ユーザーが owner かどうか
  Future<bool> isOwner(String shopId) async {
    final uid = currentUid;
    if (uid == null) return false;
    final docRef = _shopsRef.doc(shopId).collection('members').doc(uid);
    final snap = await docRef.get();
    if (!snap.exists) return false;
    final data = snap.data() ?? <String, dynamic>{};
    return (data['role'] as String?) == 'owner';
  }

  /// 招待QR作成
  Future<ShopInvite> createOneTimeInvite(String shopId) async {
    final uid = currentUid;
    if (uid == null) throw StateError('未ログインです');

    final owner = await isOwner(shopId);
    if (!owner) throw StateError('オーナーのみ招待を作成できます');

    await _cleanupInactiveInvites(shopId: shopId);

    final now = DateTime.now();
    final expiresAt = now.add(inviteTtl);

    final invitesRef = _shopsRef.doc(shopId).collection('invites');
    final inviteDocRef = invitesRef.doc();
    final inviteId = inviteDocRef.id;

    await inviteDocRef.set(<String, Object?>{
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUserId': uid,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'usedAt': null,
      'usedByUserId': null,
      'revoked': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUserId': uid,
    });

    return ShopInvite(
      shopId: shopId,
      inviteId: inviteId,
      token: inviteId,
      expiresAt: expiresAt,
    );
  }

  /// 招待QR受諾
  Future<void> acceptInvite({
    required String shopId,
    required String inviteId,
    required String token,
  }) async {
    final uid = currentUid;
    if (uid == null) throw StateError('未ログインです');
    if (token != inviteId) throw FormatException('招待情報が不正です');

    final shopRef = _shopsRef.doc(shopId);
    final inviteRef = shopRef.collection('invites').doc(inviteId);
    final memberRef = shopRef.collection('members').doc(uid);
    final membershipRef = _usersRef.doc(uid).collection('memberships').doc(shopId);
    final userRef = _usersRef.doc(uid);

    final batch = _firestore.batch();

    batch.update(inviteRef, <String, Object?>{
      'usedAt': FieldValue.serverTimestamp(),
      'usedByUserId': uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUserId': uid,
    });

    batch.set(
      memberRef,
      <String, Object?>{
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
        'addedByUserId': null,
        'joinedByInviteId': inviteId,
      },
      SetOptions(merge: true),
    );

    batch.set(
      membershipRef,
      <String, Object?>{
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
        'joinedByInviteId': inviteId,
      },
      SetOptions(merge: true),
    );

    batch.set(
      userRef,
      <String, Object?>{
        'currentShopId': shopId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// 招待失効
  Future<void> revokeInvite({
    required String shopId,
    required String inviteId,
  }) async {
    final uid = currentUid;
    if (uid == null) throw StateError('未ログインです');

    final owner = await isOwner(shopId);
    if (!owner) throw StateError('オーナーのみ招待を失効できます');

    final inviteRef = _shopsRef.doc(shopId).collection('invites').doc(inviteId);

    await inviteRef.update(<String, Object?>{
      'revoked': true,
      'revokedAt': FieldValue.serverTimestamp(),
      'revokedByUserId': uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUserId': uid,
    });
  }

  /// ★追加: よく使う売価リストを更新する（上書き）
  Future<void> updateFrequentPrices(String shopId, List<int> prices) async {
    // リストを昇順にソートして重複を排除してから保存
    final sortedUnique = prices.toSet().toList()..sort();

    await _shopsRef.doc(shopId).update({
      'frequentPrices': sortedUnique,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _cleanupInactiveInvites({required String shopId}) async {
    final invitesRef = _shopsRef.doc(shopId).collection('invites');
    final nowTs = Timestamp.fromDate(DateTime.now());

    await _deleteAllMatchingQuery(invitesRef.where('revoked', isEqualTo: true));
    await _deleteAllMatchingQuery(invitesRef.where('usedAt', isNull: false));
    await _deleteAllMatchingQuery(invitesRef.where('expiresAt', isLessThan: nowTs));
  }

  Future<void> _deleteAllMatchingQuery(Query<Map<String, dynamic>> query) async {
    while (true) {
      final snap = await query.limit(200).get();
      if (snap.docs.isEmpty) return;

      WriteBatch batch = _firestore.batch();
      int ops = 0;

      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        ops++;
        if (ops >= 450) {
          await batch.commit();
          batch = _firestore.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
    }
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}

class ShopInfo {
  const ShopInfo({required this.shopId, required this.name, this.ownerUserId});
  final String shopId;
  final String name;
  final String? ownerUserId;
}

class ShopMember {
  const ShopMember({required this.uid, required this.role, this.joinedAt, this.addedByUserId});
  final String uid;
  final String role;
  final DateTime? joinedAt;
  final String? addedByUserId;
}

class ShopInvite {
  const ShopInvite({required this.shopId, required this.inviteId, required this.token, required this.expiresAt});
  final String shopId;
  final String inviteId;
  final String token;
  final DateTime expiresAt;

  Map<String, Object?> toPayload() => {
    'type': 'shop_invite_v1',
    'shopId': shopId,
    'inviteId': inviteId,
    'token': token,
    'expiresAtMillis': expiresAt.millisecondsSinceEpoch,
  };

  static ShopInvite fromPayload(Map<String, dynamic> payload) {
    if (payload['type'] != 'shop_invite_v1') throw FormatException('QR不正');
    return ShopInvite(
      shopId: payload['shopId'],
      inviteId: payload['inviteId'],
      token: payload['token'],
      expiresAt: DateTime.fromMillisecondsSinceEpoch(payload['expiresAtMillis']),
    );
  }
}

final shopRepositoryProvider = Provider<ShopRepository>((ref) => ShopRepository());