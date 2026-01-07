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

/// 新規ユーザーや、ショップ未選択のユーザーに対して、
/// - 新しいショップを作成する（＝自分がオーナー）
/// すでにショップが選択済みのユーザーに対して、
/// - 店舗情報の確認
/// - 招待QRの発行（オーナーのみ / 使い捨て / 24時間）
/// - 招待QRの読み取り（参加）
///
/// この画面自体は「currentShopId を Firestore に書き込む」だけを担当し、
/// 画面遷移（HomeScreen への遷移など）は親側（例: AuthGate）の責務とする。
class ShopSelectionScreen extends ConsumerStatefulWidget {
  const ShopSelectionScreen({super.key});

  @override
  ConsumerState<ShopSelectionScreen> createState() =>
      _ShopSelectionScreenState();
}

class _ShopSelectionScreenState extends ConsumerState<ShopSelectionScreen> {
  final TextEditingController _newShopNameController = TextEditingController();

  final _newShopFormKey = GlobalKey<FormState>();

  bool _isCreatingShop = false;

  bool _isGeneratingInvite = false;
  bool _isAcceptingInvite = false;

  @override
  void dispose() {
    _newShopNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appUserAsync = ref.watch(appUserStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('店舗'),
      ),
      body: SafeArea(
        child: appUserAsync.when(
          data: (appUser) {
            final currentShopId = appUser?.currentShopId;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'このアプリでは「店舗」単位で在庫を共有します。\n'
                        'オーナーは招待QRを発行でき、招待を受ける側はQRを読み取って参加できます（招待QRは24時間・1回限り）。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  if (currentShopId != null && currentShopId.trim().isNotEmpty)
                    _buildCurrentShopCard(context, theme, currentShopId.trim()),
                  if (currentShopId != null && currentShopId.trim().isNotEmpty)
                    const SizedBox(height: 16),
                  if (currentShopId != null && currentShopId.trim().isNotEmpty)
                    _buildInviteCard(context, theme, currentShopId.trim()),
                  const SizedBox(height: 16),
                  _buildAcceptInviteCard(context, theme),
                  const SizedBox(height: 16),
                  _buildCreateShopCard(context, theme),
                  const SizedBox(height: 12),
                  Text(
                    '※ 招待QRは「24時間」有効で、「1回」使われると無効になります。\n'
                        '※ 店舗の共有は権限（owner/member）により制御されます。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('ユーザー情報の取得に失敗しました: $e')),
        ),
      ),
    );
  }

  Widget _buildCurrentShopCard(
      BuildContext context,
      ThemeData theme,
      String shopId,
      ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future:
          FirebaseFirestore.instance.collection('shops').doc(shopId).get(),
          builder: (context, snapshot) {
            final shopName = snapshot.data?.data()?['name'] as String?;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '現在の店舗',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  shopName == null || shopName.trim().isEmpty
                      ? '（店舗名未設定）'
                      : shopName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Shop ID: $shopId',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: shopId));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Shop ID をコピーしました')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Shop ID をコピー'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInviteCard(
      BuildContext context,
      ThemeData theme,
      String shopId,
      ) {
    final shopRepo = ref.read(shopRepositoryProvider);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<ShopMember?>(
          stream: shopRepo.watchMyMembership(shopId),
          builder: (context, snapshot) {
            final member = snapshot.data;
            final isOwner = member?.role == 'owner';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '招待QRを発行（オーナーのみ）',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'この店舗に参加するための招待QRを作成します。\n'
                      '招待QRは「24時間」有効で、「1回」使われると無効になります。',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: (!isOwner || _isGeneratingInvite)
                        ? null
                        : () => _onGenerateInviteQr(context, shopId),
                    icon: _isGeneratingInvite
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.qr_code_2),
                    label: Text(
                      _isGeneratingInvite ? '作成中...' : '招待QRを作成する',
                    ),
                  ),
                ),
                if (!isOwner) ...[
                  const SizedBox(height: 12),
                  Text(
                    '※ 招待QRの発行はオーナーのみ可能です。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAcceptInviteCard(BuildContext context, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '招待QRで参加',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'オーナーが表示している招待QRを読み取って、その店舗に参加します。\n'
                  '参加後は currentShopId が更新され、在庫一覧が対象店舗に切り替わります。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed:
                _isAcceptingInvite ? null : () => _onScanInviteQr(context),
                icon: _isAcceptingInvite
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.qr_code_scanner),
                label: Text(_isAcceptingInvite ? '参加中...' : 'QRを読み取って参加する'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateShopCard(BuildContext context, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _newShopFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '新しい店舗を作成',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '新しく店舗を作成し、作成者はオーナーになります。作成後、その店舗に切り替わります。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newShopNameController,
                decoration: const InputDecoration(
                  labelText: '店舗名',
                  hintText: '例）〇〇駄菓子店',
                ),
                textInputAction: TextInputAction.done,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '店舗名を入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed:
                  _isCreatingShop ? null : () => _onCreateNewShop(context),
                  icon: _isCreatingShop
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.store_mall_directory),
                  label: Text(_isCreatingShop ? '作成中...' : '新しい店舗を作成する'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 新しいショップを作成し、
  /// - shops/{shopId} を作る
  /// - shops/{shopId}/members/{uid} を role=owner で作る（正本）
  /// - users/{uid}/memberships/{shopId} を role=owner で作る（参照）
  /// - users/{uid}.currentShopId を更新する
  Future<void> _onCreateNewShop(BuildContext context) async {
    if (_isCreatingShop) return;

    if (!_newShopFormKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ログイン情報が見つかりません。再ログインしてください。'),
        ),
      );
      return;
    }

    final String shopName = _newShopNameController.text.trim();

    setState(() {
      _isCreatingShop = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final shopsRef = firestore.collection('shops');
      final usersRef = firestore.collection('users');

      // shops コレクションに新しいショップを作成
      final shopDocRef = await shopsRef.add(<String, Object?>{
        'name': shopName,
        'ownerUserId': user.uid,
        'createdByUserId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUserId': user.uid,
      });

      final String newShopId = shopDocRef.id;

      // members（正本）と memberships（参照）と currentShopId をまとめて作成
      final batch = firestore.batch();

      final memberRef =
      shopsRef.doc(newShopId).collection('members').doc(user.uid);
      batch.set(memberRef, <String, Object?>{
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
        'addedByUserId': user.uid,
      });

      final membershipRef =
      usersRef.doc(user.uid).collection('memberships').doc(newShopId);
      batch.set(membershipRef, <String, Object?>{
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
        'shopNameCache': shopName,
      });

      // users/{uid}.currentShopId を新しいショップIDに更新（merge）
      batch.set(
        usersRef.doc(user.uid),
        <String, Object?>{
          'currentShopId': newShopId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('新しい店舗「$shopName」を作成しました'),
        ),
      );

      // メニューから開いている場合は戻す（戻った先でAuthGateが切り替える）
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('店舗の作成に失敗しました: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isCreatingShop = false;
      });
    }
  }

  Future<void> _onGenerateInviteQr(BuildContext context, String shopId) async {
    if (_isGeneratingInvite) return;

    setState(() {
      _isGeneratingInvite = true;
    });

    try {
      final shopRepo = ref.read(shopRepositoryProvider);
      final invite = await shopRepo.createOneTimeInvite(shopId);

      final payloadJson = jsonEncode(invite.toPayload());

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return _InviteQrDialog(
            payloadJson: payloadJson,
            invite: invite,
            onCopy: () async {
              await Clipboard.setData(ClipboardData(text: payloadJson));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('招待データ（JSON）をコピーしました')),
              );
            },
            onRevoke: () async {
              try {
                await shopRepo.revokeInvite(
                  shopId: invite.shopId,
                  inviteId: invite.inviteId,
                );
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('招待を失効しました')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('招待の失効に失敗しました: $e')),
                );
              }
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('招待QRの作成に失敗しました: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isGeneratingInvite = false;
      });
    }
  }

  Future<void> _onScanInviteQr(BuildContext context) async {
    if (_isAcceptingInvite) return;

    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const _InviteQrScanScreen(),
      ),
    );

    if (scanned == null || scanned.trim().isEmpty) return;

    setState(() {
      _isAcceptingInvite = true;
    });

    try {
      // QR は JSON 文字列（ShopInvite.toPayload を jsonEncode したもの）を想定
      final dynamic decoded = jsonDecode(scanned);
      if (decoded is! Map) {
        throw const FormatException('QRの形式が不正です（JSONオブジェクトではありません）');
      }

      final payload = decoded.cast<String, dynamic>();
      final invite = ShopInvite.fromPayload(payload);

      // 期限切れはクライアント側でも弾く（サーバー側でも弾く）
      if (invite.expiresAt.isBefore(DateTime.now())) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('この招待QRは期限切れです（24時間）')),
        );
        return;
      }

      // Firestoreで受諾（招待を使用済みにし、members/memberships/currentShopId を更新する）
      final shopRepo = ref.read(shopRepositoryProvider);
      await shopRepo.acceptInvite(
        shopId: invite.shopId,
        inviteId: invite.inviteId,
        token: invite.token,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('店舗に参加しました')),
      );

      // メニューから開いている場合は戻す（戻った先で切り替えが起きる）
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('店舗への参加に失敗しました: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isAcceptingInvite = false;
      });
    }
  }
}

class _InviteQrDialog extends StatelessWidget {
  const _InviteQrDialog({
    required this.payloadJson,
    required this.invite,
    required this.onCopy,
    required this.onRevoke,
  });

  final String payloadJson;
  final ShopInvite invite;
  final VoidCallback onCopy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiresText = invite.expiresAt.toLocal().toString().split('.').first;

    // AlertDialog は内部で intrinsic 計測を行うことがあり、
    // qr_flutter の QrImageView（内部で LayoutBuilder を利用）と相性が悪く
    // 「LayoutBuilder does not support returning intrinsic dimensions」が発生する。
    // そのため、Dialog + 固定サイズの SizedBox で安全に表示する。
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 420,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '招待QR（1回限り・24時間）',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 240,
                  height: 240,
                  child: QrImageView(
                    data: payloadJson,
                    version: QrVersions.auto,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '有効期限: $expiresText',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '※ このQRは1回使われると無効になります。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onCopy,
                      child: const Text('コピー'),
                    ),
                    TextButton(
                      onPressed: onRevoke,
                      child: const Text('失効'),
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
        ),
      ),
    );
  }
}

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
      appBar: AppBar(
        title: const Text('招待QRを読み取る'),
      ),
      body: MobileScanner(
        controller: MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
          facing: CameraFacing.back,
        ),
        onDetect: (capture) {
          if (_detected) return;
          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;

          final raw = barcodes.first.rawValue;
          if (raw == null || raw.trim().isEmpty) return;

          _detected = true;
          Navigator.of(context).pop(raw);
        },
      ),
    );
  }
}
