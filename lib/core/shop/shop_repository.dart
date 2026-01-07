import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ショップ関連（メンバー判定 / 招待QR発行 / QR受諾）を扱うリポジトリ。
///
/// 【重要】Sparkプラン前提のため Cloud Functions は使わない。
/// Firestore の invites を使って「24時間・1回限り」の招待を実現する。
///
/// セキュリティ方針:
/// - 在庫(snacks)のread/write権限は shops/{shopId}/members/{uid} を正本として判定する
/// - 招待QRは shops/{shopId}/invites/{inviteId} を作成し、inviteId を秘密値として扱う
///   （= QRに shopId + inviteId を入れる。tokenは inviteId と同一扱い）
/// - 参加時は batched write で invite を used にしつつ、members/memberships/currentShopId を更新する
/// - 「使い捨て」や「期限(24h)」の厳密な強制は Firestore Security Rules 側で行う（後のステップ）
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

  /// shops/{shopId} を取得（存在しない場合は null）
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

  /// shops/{shopId}/members/{uid} を監視（存在しない場合は null）
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

  /// 現在ユーザーが owner かどうか（members正本で判定）
  Future<bool> isOwner(String shopId) async {
    final uid = currentUid;
    if (uid == null) return false;
    final docRef = _shopsRef.doc(shopId).collection('members').doc(uid);
    final snap = await docRef.get();
    if (!snap.exists) return false;
    final data = snap.data() ?? <String, dynamic>{};
    return (data['role'] as String?) == 'owner';
  }

  /// 招待QR（使い捨て・有効期限24時間）を作成する（Firestoreのみ）。
  ///
  /// - shops/{shopId}/invites/{inviteId} を作成
  /// - inviteId を秘密値として扱う（token として返す）
  ///
  /// Firestore（推奨）フィールド:
  /// - createdAt / createdByUserId
  /// - expiresAt（now+24h）
  /// - usedAt / usedByUserId（未使用は null）
  /// - revoked（false）
  ///
  /// 【注意】オーナー判定・作成権限は Rules 側でも必ず制約すること。
  ///
  /// 【追加仕様】invites にゴミが溜まらないよう、
  /// 期限切れ/使用済み/revoked の「有効ではない招待」を全削除してから新規作成する。
  Future<ShopInvite> createOneTimeInvite(String shopId) async {
    final uid = currentUid;
    if (uid == null) {
      throw StateError('未ログインです');
    }

    // UI側ではオーナーのみボタンを有効化しているが、念のためガード
    final owner = await isOwner(shopId);
    if (!owner) {
      throw StateError('オーナーのみ招待を作成できます');
    }

    // 有効ではない招待（期限切れ・使用済み・revoked）を全削除
    await _cleanupInactiveInvites(shopId: shopId);

    final now = DateTime.now();
    final expiresAt = now.add(inviteTtl);

    final invitesRef = _shopsRef.doc(shopId).collection('invites');
    final inviteDocRef = invitesRef.doc(); // 自動ID（推測困難）
    final inviteId = inviteDocRef.id;

    await inviteDocRef.set(<String, Object?>{
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUserId': uid,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'usedAt': null,
      'usedByUserId': null,
      'revoked': false,
      // 追加情報（任意）
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUserId': uid,
    });

    // SparkプランではFunctionsが無いので、tokenは inviteId と同一扱い（秘密はIDそのもの）
    return ShopInvite(
      shopId: shopId,
      inviteId: inviteId,
      token: inviteId,
      expiresAt: expiresAt,
    );
  }

  /// 招待QRを受諾して、そのショップの member になる（Firestoreのみ）。
  ///
  /// batched write で以下を同時に実行：
  /// - invites/{inviteId} を used に更新（usedAt/usedByUserId）
  /// - shops/{shopId}/members/{uid} を作成（role=member）
  /// - users/{uid}/memberships/{shopId} を作成（role=member）
  /// - users/{uid}.currentShopId を shopId に更新
  ///
  /// 【重要】「期限内」「未使用」「1回限り」「revoked=false」の厳密判定は Rules 側で行う。
  ///
  /// 【追加（本番用の締め）】
  /// members / memberships に joinedByInviteId を残すことで、
  /// Rules 側で「招待が有効な時だけ参加できる」検証が可能になる。
  Future<void> acceptInvite({
    required String shopId,
    required String inviteId,
    required String token,
  }) async {
    final uid = currentUid;
    if (uid == null) {
      throw StateError('未ログインです');
    }

    // Spark版の設計では token == inviteId（秘密はinviteIdそのもの）
    if (token != inviteId) {
      throw FormatException('招待情報が不正です（token不一致）');
    }

    final shopRef = _shopsRef.doc(shopId);
    final inviteRef = shopRef.collection('invites').doc(inviteId);
    final memberRef = shopRef.collection('members').doc(uid);
    final membershipRef =
    _usersRef.doc(uid).collection('memberships').doc(shopId);
    final userRef = _usersRef.doc(uid);

    final batch = _firestore.batch();

    // 招待を使用済みにする（1回限り）
    batch.update(inviteRef, <String, Object?>{
      'usedAt': FieldValue.serverTimestamp(),
      'usedByUserId': uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUserId': uid,
    });

    // members（正本）
    // 既に存在する可能性があるので merge にして安全に
    batch.set(
      memberRef,
      <String, Object?>{
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
        // addedByUserId は Functions が無いと確実に入れづらいので null 許容で運用
        'addedByUserId': null,

        // ★ 追加：どの招待で参加したか（Rulesで検証するためのキー）
        'joinedByInviteId': inviteId,
      },
      SetOptions(merge: true),
    );

    // memberships（参照）
    batch.set(
      membershipRef,
      <String, Object?>{
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),

        // ★ 追加：参照側にも残しておく（将来のUI/監査用）
        'joinedByInviteId': inviteId,
      },
      SetOptions(merge: true),
    );

    // currentShopId 更新
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

  /// 招待QRを失効させる（Firestoreのみ）。
  ///
  /// - revoked=true にする（未使用でも使用済みでも可。ただし運用上は未使用のみ想定）
  /// - オーナーのみ実行できるよう Rules で制約する
  Future<void> revokeInvite({
    required String shopId,
    required String inviteId,
  }) async {
    final uid = currentUid;
    if (uid == null) {
      throw StateError('未ログインです');
    }

    final owner = await isOwner(shopId);
    if (!owner) {
      throw StateError('オーナーのみ招待を失効できます');
    }

    final inviteRef = _shopsRef.doc(shopId).collection('invites').doc(inviteId);

    await inviteRef.update(<String, Object?>{
      'revoked': true,
      'revokedAt': FieldValue.serverTimestamp(),
      'revokedByUserId': uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUserId': uid,
    });
  }

  /// invites に溜まる「有効ではない招待」を全削除する。
  ///
  /// 対象:
  /// - revoked == true
  /// - usedAt != null
  /// - expiresAt < now
  ///
  /// ※ Sparkプラン（Functions無し）のため、クライアント起点でのGC。
  /// ※ 実行者は createOneTimeInvite() 側で owner チェック済みを前提。
  Future<void> _cleanupInactiveInvites({required String shopId}) async {
    final invitesRef = _shopsRef.doc(shopId).collection('invites');
    final now = DateTime.now();
    final nowTs = Timestamp.fromDate(now);

    // 1) revoked
    await _deleteAllMatchingQuery(
      invitesRef.where('revoked', isEqualTo: true),
    );

    // 2) used
    await _deleteAllMatchingQuery(
      invitesRef.where('usedAt', isNull: false),
    );

    // 3) expired
    await _deleteAllMatchingQuery(
      invitesRef.where('expiresAt', isLessThan: nowTs),
    );
  }

  /// クエリに一致するドキュメントを全削除する（500制限に配慮して分割）。
  Future<void> _deleteAllMatchingQuery(
      Query<Map<String, dynamic>> query,
      ) async {
    // 1回の取得は小さめにして繰り返す（削除し切るまで）
    while (true) {
      final snap = await query.limit(200).get();
      if (snap.docs.isEmpty) return;

      WriteBatch batch = _firestore.batch();
      int ops = 0;

      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        ops++;

        // Firestoreのバッチ上限(500)より余裕を持ってコミット
        if (ops >= 450) {
          await batch.commit();
          batch = _firestore.batch();
          ops = 0;
        }
      }

      if (ops > 0) {
        await batch.commit();
      }

      // ループして次の塊も削除する
    }
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }
}

class ShopInfo {
  const ShopInfo({
    required this.shopId,
    required this.name,
    this.ownerUserId,
  });

  final String shopId;
  final String name;
  final String? ownerUserId;
}

class ShopMember {
  const ShopMember({
    required this.uid,
    required this.role,
    this.joinedAt,
    this.addedByUserId,
  });

  final String uid;
  final String role; // owner / member
  final DateTime? joinedAt;
  final String? addedByUserId;
}

/// QRに埋め込む招待情報（使い捨て）
///
/// Sparkプラン版では「秘密」は inviteId（Firestore自動ID）そのもの。
/// token は inviteId と同一の値として扱う。
class ShopInvite {
  const ShopInvite({
    required this.shopId,
    required this.inviteId,
    required this.token,
    required this.expiresAt,
  });

  final String shopId;
  final String inviteId;
  final String token;
  final DateTime expiresAt;

  Map<String, Object?> toPayload() {
    return <String, Object?>{
      'type': 'shop_invite_v1',
      'shopId': shopId,
      'inviteId': inviteId,
      'token': token,
      'expiresAtMillis': expiresAt.millisecondsSinceEpoch,
    };
  }

  static ShopInvite fromPayload(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;
    if (type != 'shop_invite_v1') {
      throw FormatException('QRの形式が不正です（type不一致）: $type');
    }

    final shopId = payload['shopId'] as String?;
    final inviteId = payload['inviteId'] as String?;
    final token = payload['token'] as String?;
    final expiresAtMillis = payload['expiresAtMillis'] as int?;

    if (shopId == null ||
        shopId.isEmpty ||
        inviteId == null ||
        inviteId.isEmpty ||
        token == null ||
        token.isEmpty ||
        expiresAtMillis == null) {
      throw FormatException('QRの内容が不足しています: $payload');
    }

    return ShopInvite(
      shopId: shopId,
      inviteId: inviteId,
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMillis),
    );
  }
}

final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  return ShopRepository();
});
