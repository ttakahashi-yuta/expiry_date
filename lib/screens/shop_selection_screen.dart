import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 新規ユーザーや、ショップ未選択のユーザーに対して、
/// - 新しいショップを作成する
/// - 既存のショップIDを入力して参加する
/// ための画面。
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
  final TextEditingController _newShopNameController =
  TextEditingController();
  final TextEditingController _joinShopIdController =
  TextEditingController();

  final _newShopFormKey = GlobalKey<FormState>();
  final _joinShopFormKey = GlobalKey<FormState>();

  bool _isCreatingShop = false;
  bool _isJoiningShop = false;

  @override
  void dispose() {
    _newShopNameController.dispose();
    _joinShopIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('お店を選択'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'このアプリでは「ショップ」単位で在庫を共有します。\n'
                    '新しくお店を作成するか、既に作成済みのお店IDを入力して参加してください。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),

              // 新しいショップを作成
              Card(
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
                          '新しいお店を作成',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '駄菓子屋さんを新しくこのアプリで管理したい場合は、こちらからお店を作成します。',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _newShopNameController,
                          decoration: const InputDecoration(
                            labelText: 'お店の名前',
                            hintText: '例）〇〇駄菓子店',
                          ),
                          textInputAction: TextInputAction.done,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'お店の名前を入力してください';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 44,
                          child: FilledButton.icon(
                            onPressed: _isCreatingShop
                                ? null
                                : () => _onCreateNewShop(context),
                            icon: _isCreatingShop
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                                : const Icon(Icons.store_mall_directory),
                            label: Text(
                              _isCreatingShop
                                  ? '作成中...'
                                  : '新しいお店を作成する',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 既存のショップに参加
              Card(
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
                    key: _joinShopFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '既存のお店に参加',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'すでに誰かが作成したお店を一緒に管理する場合は、'
                              'そのお店のIDを入力して参加します。',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _joinShopIdController,
                          decoration: const InputDecoration(
                            labelText: 'お店ID',
                            hintText: '例）shops コレクションのドキュメントID',
                          ),
                          textInputAction: TextInputAction.done,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'お店IDを入力してください';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: _isJoiningShop
                                ? null
                                : () => _onJoinExistingShop(context),
                            icon: _isJoiningShop
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                                : const Icon(Icons.login),
                            label: Text(
                              _isJoiningShop
                                  ? '参加中...'
                                  : 'このお店に参加する',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Text(
                '※ お店IDは、shops コレクションのドキュメントIDを想定しています。\n'
                    '　将来的には招待コードなどの仕組みに置き換えることもできます。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 新しいショップを作成し、users/{uid}.currentShopId に紐づける。
  Future<void> _onCreateNewShop(BuildContext context) async {
    if (_isCreatingShop) return;

    if (!_newShopFormKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログイン情報が見つかりません。再ログインしてください。')),
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

      // shops コレクションに新しいショップを作成
      final shopDocRef = await shopsRef.add(<String, Object?>{
        'name': shopName,
        'ownerUserId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final String newShopId = shopDocRef.id;

      // users/{uid}.currentShopId を新しいショップIDに更新（merge）
      final usersRef = firestore.collection('users');
      await usersRef.doc(user.uid).set(
        <String, Object?>{
          'currentShopId': newShopId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('新しいお店「$shopName」を作成しました（ID: $newShopId）'),
        ),
      );

      // 画面遷移自体は親（AuthGate）側に任せる。
      // currentShopId が更新されれば、appUserStreamProvider 経由で
      // HomeScreen への切り替えが行われる想定。
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('お店の作成に失敗しました: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isCreatingShop = false;
      });
    }
  }

  /// 既存のショップIDを使って、そのショップに参加する。
  ///
  /// shops/{shopId} が存在する場合にのみ、users/{uid}.currentShopId を更新する。
  Future<void> _onJoinExistingShop(BuildContext context) async {
    if (_isJoiningShop) return;

    if (!_joinShopFormKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログイン情報が見つかりません。再ログインしてください。')),
      );
      return;
    }

    final String inputShopId = _joinShopIdController.text.trim();

    setState(() {
      _isJoiningShop = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final shopDocRef = firestore.collection('shops').doc(inputShopId);
      final shopSnapshot = await shopDocRef.get();

      if (!shopSnapshot.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('指定されたお店IDは存在しません。'),
          ),
        );
        return;
      }

      // users/{uid}.currentShopId をこのショップIDに更新（merge）
      final usersRef = firestore.collection('users');
      await usersRef.doc(user.uid).set(
        <String, Object?>{
          'currentShopId': inputShopId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      final shopName = shopSnapshot.data()?['name'] as String? ?? 'お店';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('「$shopName」に参加しました（ID: $inputShopId）'),
        ),
      );

      // 画面遷移自体は親（AuthGate）側に任せる。
      // currentShopId の更新により、HomeScreen への切り替えが行われる想定。
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('お店への参加に失敗しました: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isJoiningShop = false;
      });
    }
  }
}
