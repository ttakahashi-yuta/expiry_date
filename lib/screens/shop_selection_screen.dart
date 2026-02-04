import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:expiry_date/core/shop/shop_repository.dart';
import 'package:expiry_date/core/user/user_providers.dart';

/// 店舗選択・管理画面
class ShopSelectionScreen extends ConsumerStatefulWidget {
  const ShopSelectionScreen({super.key});

  @override
  ConsumerState<ShopSelectionScreen> createState() => _ShopSelectionScreenState();
}

class _ShopSelectionScreenState extends ConsumerState<ShopSelectionScreen> {
  // ローディング状態管理
  bool _isGeneratinInvite = false;
  bool _isAcceptingInvite = false;
  bool _isCreatingShop = false;

  @override
  Widget build(BuildContext context) {
    final appUserAsync = ref.watch(appUserStreamProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('店舗設定')),
      backgroundColor: theme.colorScheme.surface, // 背景色
      body: appUserAsync.when(
        data: (appUser) {
          final currentShopId = appUser?.currentShopId;
          final hasShop = currentShopId != null && currentShopId.trim().isNotEmpty;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              // 1. 現在の店舗ヘッダー（店舗がある場合のみ）
              if (hasShop) ...[
                _buildCurrentShopHeader(context, currentShopId!),
                const SizedBox(height: 24),
              ],

              // 2. 切り替え・参加アクション
              _SectionHeader(title: 'アクション'),
              // ★追加予定の「店舗切り替え」
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('店舗を切り替える'),
                subtitle: const Text('参加済みの他の店舗へ移動します'),
                trailing: const Chip(label: Text('準備中', style: TextStyle(fontSize: 10))),
                enabled: false, // まだ押せない
                onTap: () {
                  // TODO: 店舗切り替えダイアログの実装
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('招待QRを読み取る'),
                subtitle: const Text('カメラを起動して店舗に参加します'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _isAcceptingInvite ? null : () => _onScanInviteQr(context),
              ),
              ListTile(
                leading: const Icon(Icons.add_business),
                title: const Text('新しい店舗を作成'),
                subtitle: const Text('新しく店舗を作り、オーナーになります'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _isCreatingShop ? null : () => _showCreateShopDialog(context),
              ),

              if (hasShop) ...[
                const Divider(height: 32),
                // 3. オーナー用メニュー
                _SectionHeader(title: '現在の店舗の管理'),
                _buildOwnerMenu(context, currentShopId),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
      ),
    );
  }

  /// 現在の店舗情報を表示するカード
  Widget _buildCurrentShopHeader(BuildContext context, String shopId) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('shops').doc(shopId).get(),
        builder: (context, snapshot) {
          final shopName = snapshot.data?.data()?['name'] as String? ?? '読み込み中...';

          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.store, color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      '現在の店舗',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  shopName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: shopId));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Shop ID をコピーしました')),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ID: $shopId',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer.withOpacity(0.7),
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.copy, size: 14, color: theme.colorScheme.onPrimaryContainer.withOpacity(0.7)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// オーナー向けメニュー（メンバーシップを確認して表示）
  Widget _buildOwnerMenu(BuildContext context, String shopId) {
    final shopRepo = ref.read(shopRepositoryProvider);

    return StreamBuilder<ShopMember?>(
      stream: shopRepo.watchMyMembership(shopId),
      builder: (context, snapshot) {
        final member = snapshot.data;
        final isOwner = member?.role == 'owner';

        if (!isOwner) {
          return const ListTile(
            leading: Icon(Icons.lock_outline, color: Colors.grey),
            title: Text('招待QRの発行', style: TextStyle(color: Colors.grey)),
            subtitle: Text('オーナーのみ利用可能です'),
          );
        }

        return ListTile(
          leading: const Icon(Icons.qr_code_2),
          title: const Text('招待QRを発行'),
          subtitle: const Text('スタッフ招待用のQRコードを表示します'),
          trailing: _isGeneratinInvite
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.chevron_right),
          onTap: _isGeneratinInvite ? null : () => _onGenerateInviteQr(context, shopId),
        );
      },
    );
  }

  // ==========================================
  // ロジック（ダイアログ表示など）
  // ==========================================

  /// 新規店舗作成ダイアログ
  Future<void> _showCreateShopDialog(BuildContext context) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新しい店舗を作成'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '店舗名',
              hintText: '例）〇〇駄菓子店',
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? '入力してください' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(); // ダイアログを閉じる
                await _onCreateNewShop(context, controller.text.trim()); // 作成処理へ
              }
            },
            child: const Text('作成'),
          ),
        ],
      ),
    );
  }

  Future<void> _onCreateNewShop(BuildContext context, String shopName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isCreatingShop = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final shopsRef = firestore.collection('shops');
      final usersRef = firestore.collection('users');

      // 1. 店舗作成
      final shopDocRef = await shopsRef.add({
        'name': shopName,
        'ownerUserId': user.uid,
        'createdByUserId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUserId': user.uid,
      });

      final newShopId = shopDocRef.id;
      final batch = firestore.batch();

      // 2. メンバー追加（正本）
      batch.set(
        shopsRef.doc(newShopId).collection('members').doc(user.uid),
        {
          'role': 'owner',
          'joinedAt': FieldValue.serverTimestamp(),
          'addedByUserId': user.uid,
        },
      );

      // 3. メンバーシップ追加（参照）
      batch.set(
        usersRef.doc(user.uid).collection('memberships').doc(newShopId),
        {
          'role': 'owner',
          'joinedAt': FieldValue.serverTimestamp(),
          'shopNameCache': shopName,
        },
      );

      // 4. 現在の店舗を更新
      batch.set(
        usersRef.doc(user.uid),
        {
          'currentShopId': newShopId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('店舗「$shopName」を作成しました')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('作成に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreatingShop = false);
    }
  }

  Future<void> _onGenerateInviteQr(BuildContext context, String shopId) async {
    setState(() => _isGeneratinInvite = true);

    try {
      final shopRepo = ref.read(shopRepositoryProvider);
      final invite = await shopRepo.createOneTimeInvite(shopId);
      final payloadJson = jsonEncode(invite.toPayload());

      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (_) => _InviteQrDialog(
          payloadJson: payloadJson,
          invite: invite,
          onRevoke: () async {
            await shopRepo.revokeInvite(shopId: invite.shopId, inviteId: invite.inviteId);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGeneratinInvite = false);
    }
  }

  Future<void> _onScanInviteQr(BuildContext context) async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _InviteQrScanScreen()),
    );

    if (scanned == null || scanned.trim().isEmpty) return;

    setState(() => _isAcceptingInvite = true);

    try {
      final dynamic decoded = jsonDecode(scanned);
      if (decoded is! Map) throw const FormatException('QR形式エラー');

      final payload = decoded.cast<String, dynamic>();
      final invite = ShopInvite.fromPayload(payload);

      if (invite.expiresAt.isBefore(DateTime.now())) {
        throw const FormatException('期限切れの招待QRです');
      }

      await ref.read(shopRepositoryProvider).acceptInvite(
        shopId: invite.shopId,
        inviteId: invite.inviteId,
        token: invite.token,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('店舗に参加しました')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('参加に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAcceptingInvite = false);
    }
  }
}

// ==========================================
// ヘルパーウィジェット
// ==========================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 招待QR表示ダイアログ
class _InviteQrDialog extends StatelessWidget {
  const _InviteQrDialog({
    required this.payloadJson,
    required this.invite,
    required this.onRevoke,
  });

  final String payloadJson;
  final ShopInvite invite;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '招待QR',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('スキャンして参加（24時間有効）', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(data: payloadJson, version: QrVersions.auto),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onRevoke,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('無効化する'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// QRスキャン画面
class _InviteQrScanScreen extends StatefulWidget {
  const _InviteQrScanScreen();

  @override
  State<_InviteQrScanScreen> createState() => _InviteQrScanScreenState();
}

class _InviteQrScanScreenState extends State<_InviteQrScanScreen> {
  bool _detected = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QRをスキャン')),
      body: MobileScanner(
        controller: MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
          facing: CameraFacing.back,
        ),
        onDetect: (capture) {
          if (_detected) return;
          final val = capture.barcodes.first.rawValue;
          if (val != null) {
            _detected = true;
            Navigator.of(context).pop(val);
          }
        },
      ),
    );
  }
}