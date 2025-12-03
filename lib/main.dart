import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:expiry_date/models/snack_item.dart';
import 'package:expiry_date/screens/settings_screen.dart';
import 'package:expiry_date/core/settings/app_settings.dart';
import 'package:expiry_date/screens/add_snack_flow_screen.dart';
import 'package:expiry_date/core/user/user_providers.dart';
import 'package:expiry_date/core/user/user_repository.dart';
import 'package:expiry_date/screens/shop_selection_screen.dart';

import 'firebase_options.dart';
import 'core/auth/auth_repository.dart';
import 'screens/sign_in_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: ExpiryDateApp()));
}

class ExpiryDateApp extends StatelessWidget {
  const ExpiryDateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '賞味期限管理',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.orange,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          surfaceTintColor: Colors.transparent, // ←色変化防止
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// FirebaseAuth / Firestore の状態に応じて
/// - 未ログイン: SignInScreen
/// - ログイン済み & ショップ未選択: ShopSelectionScreen
/// - ログイン済み & ショップ選択済み: 在庫一覧画面（HomeScreen）
/// を出し分けるゲート。
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    final appUserAsync = ref.watch(appUserStreamProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          // 未ログイン → ログイン画面へ
          return const SignInScreen();
        }

        // ログイン済み → users/{uid} を必ず作成しておく（fire-and-forget）
        final userRepo = ref.read(userRepositoryProvider);
        userRepo.ensureUserDocument(user);

        // Firestore の users/{uid} ドキュメントを見て、
        // currentShopId の有無で画面を出し分ける。
        return appUserAsync.when(
          data: (appUser) {
            if (appUser == null) {
              // users/{uid} ドキュメントがまだ無い／読み込み中
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final currentShopId = appUser.currentShopId;

            // null または 空文字 は「ショップ未選択」とみなす
            if (currentShopId == null || currentShopId.isEmpty) {
              return const ShopSelectionScreen();
            }

            // ショップ選択済み → 在庫一覧画面へ
            return const HomeScreen();
          },
          loading: () {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          },
          error: (error, stack) {
            return Scaffold(
              body: Center(
                child: Text('ユーザー情報の取得中にエラーが発生しました: $error'),
              ),
            );
          },
        );
      },
      loading: () {
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
      error: (error, stack) {
        return Scaffold(
          body: Center(
            child: Text('認証エラーが発生しました: $error'),
          ),
        );
      },
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // ← ここで一度だけ取得しておく（安全な ancestor から）
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    // 現在のユーザーが操作している shopId を取得
    final shopId = ref.watch(currentShopIdProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text(
          '在庫一覧（賞味期限順）',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  break;
                case 'help':
                // TODO: ヘルプ画面
                  break;
                case 'about':
                // TODO: このアプリについて
                  break;
                case 'logout':
                // ログアウト
                  final authRepo = ref.read(authRepositoryProvider);
                  await authRepo.signOut();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: Text('設定'),
              ),
              PopupMenuItem(
                value: 'help',
                child: Text('ヘルプ'),
              ),
              PopupMenuItem(
                value: 'about',
                child: Text('このアプリについて'),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Text('ログアウト'),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),

      // =======================
      // メインリスト部分
      // =======================
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db
            .collection('shops')
            .doc(shopId)
            .collection('snacks')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('在庫の取得中にエラーが発生しました: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          // Firestore のドキュメントから SnackItem のリストを作成
          final entries = docs.map((doc) {
            final data = doc.data();
            final expiryTs = data['expiry'] as Timestamp?;
            final expiry = expiryTs?.toDate() ?? DateTime.now();

            final snack = SnackItem(
              name: data['name'] as String? ?? '',
              expiry: expiry,
              janCode: data['janCode'] as String?,
              price: (data['price'] as num?)?.toInt(),
            );

            return _SnackDocEntry(
              docId: doc.id,
              snack: snack,
            );
          }).toList();

          // 賞味期限順にソート
          entries.sort(
                (a, b) => a.snack.expiry.compareTo(b.snack.expiry),
          );

          // ステータス別カウント
          int expiredCount = 0;
          int soonCount = 0;
          int safeCount = 0;

          for (final entry in entries) {
            final daysLeft = entry.snack.expiry.difference(now).inDays;
            if (daysLeft < 0) {
              expiredCount++;
            } else if (daysLeft <= 7) {
              soonCount++;
            } else {
              safeCount++;
            }
          }

          final confirmDelete = ref.watch(confirmDeleteProvider);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 16.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatusIndicator(
                        Icons.error, Colors.red, '期限切れ', expiredCount),
                    _buildStatusIndicator(
                        Icons.warning, Colors.amber, 'もうすぐ', soonCount),
                    _buildStatusIndicator(
                        Icons.check_circle, Colors.green, '余裕あり', safeCount),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? const Center(
                  child: Text(
                    'まだ在庫が登録されていません。\n下の＋ボタンから追加してください。',
                    textAlign: TextAlign.center,
                  ),
                )
                    : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final snack = entry.snack;
                    final daysLeft =
                        snack.expiry.difference(now).inDays;
                    final isExpired = daysLeft < 0;

                    final Color backgroundColor;
                    if (isExpired) {
                      backgroundColor = Colors.red.shade50;
                    } else if (daysLeft <= 7) {
                      backgroundColor = Colors.amber.shade50;
                    } else {
                      backgroundColor = Colors.green.shade50;
                    }

                    return Dismissible(
                      key: ValueKey(entry.docId),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        color: Colors.red.shade400,
                        padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(
                          Icons.delete_forever,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      confirmDismiss: (direction) async {
                        if (!confirmDelete) {
                          // 削除確認OFF → 即削除
                          return true;
                        }
                        // 削除確認ON → ダイアログ表示
                        return await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('削除の確認'),
                            content: Text(
                                '「${snack.name}」を削除しますか？'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context)
                                        .pop(false),
                                child: const Text('キャンセル'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text(
                                  '削除',
                                  style:
                                  TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ) ??
                            false;
                      },
                      onDismissed: (direction) async {
                        final deletedEntry = entry;

                        try {
                          await _db
                              .collection('shops')
                              .doc(shopId)
                              .collection('snacks')
                              .doc(entry.docId)
                              .delete();
                        } catch (e) {
                          if (!mounted) return;
                          scaffoldMessenger.clearSnackBars();
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                  '在庫の削除に失敗しました: $e'),
                            ),
                          );
                          return;
                        }

                        if (!mounted) return;
                        scaffoldMessenger.clearSnackBars();
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(
                                '「${deletedEntry.snack.name}」を削除しました'),
                            action: SnackBarAction(
                              label: '元に戻す',
                              onPressed: () async {
                                final user = FirebaseAuth
                                    .instance.currentUser;
                                try {
                                  await _db
                                      .collection('shops')
                                      .doc(shopId)
                                      .collection('snacks')
                                      .doc(deletedEntry.docId)
                                      .set({
                                    'name': deletedEntry.snack.name,
                                    'expiry': Timestamp.fromDate(
                                        deletedEntry.snack.expiry),
                                    'janCode':
                                    deletedEntry.snack.janCode,
                                    'price': deletedEntry.snack.price,
                                    'createdAt':
                                    FieldValue.serverTimestamp(),
                                    'createdByUserId': user?.uid,
                                  });
                                } catch (e) {
                                  if (!mounted) return;
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '元に戻す処理に失敗しました: $e'),
                                    ),
                                  );
                                }
                              },
                            ),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      },
                      child: _buildSnackCard(
                        snack,
                        daysLeft,
                        backgroundColor,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar:
      _buildBottomActionBar(context, scaffoldMessenger, shopId),
    );
  }

  /// 駄菓子カードUI
  Widget _buildSnackCard(
      SnackItem snack, int daysLeft, Color backgroundColor) {
    final bool isExpired = daysLeft < 0;
    final String expiryText =
    snack.expiry.toLocal().toString().split(' ')[0]; // yyyy-MM-dd 部分だけ

    // 左ボックス用：背景色と同系色で少し濃い枠線色を計算
    final hsl = HSLColor.fromColor(backgroundColor);
    final Color boxBorderColor = hsl
        .withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0))
        .toColor();

    return Container(
      decoration: BoxDecoration(
        // カードの背景色は白に固定
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 0.5),
          bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左側：残り◯日 / 期限切れ ボックス
          Container(
            width: 80,
            height: 72,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              // カードに渡されていた背景色をボックスの背景色として使う
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: boxBorderColor, // 背景色より少し濃い同系色
                width: 1.2,
              ),
            ),
            child: Center(
              child: isExpired
                  ? const Text(
                '期限切れ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black, // 黒文字
                ),
              )
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '残り',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black, // 黒文字に変更
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 数字と「日」を1つの Text.rich でベースライン揃え
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$daysLeft',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black, // 黒文字
                          ),
                        ),
                        const TextSpan(
                          text: '日',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black, // 黒文字
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          // 右側：商品名 / （賞味期限 ＋ 売価）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 商品名（1行目）
                Text(
                  snack.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                // 賞味期限 ＋ 売価（1行に横並び）
                Row(
                  children: [
                    // 賞味期限側にしっかり幅を確保（見切れないよう Expanded）
                    Expanded(
                      child: Text(
                        '賞味期限: $expiryText',
                        style: const TextStyle(
                          fontSize: 16, // 少し大きめ
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        // overflow は付けない：全部表示したいので
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 売価は右寄せでコンパクトに
                    Text(
                      snack.price != null ? '${snack.price}円' : '未設定',
                      style: const TextStyle(
                        fontSize: 16, // 賞味期限と揃える
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 状態アイコンバー
  Widget _buildStatusIndicator(
      IconData icon, Color color, String label, int count) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }

  Widget _buildBottomActionBar(
      BuildContext context,
      ScaffoldMessengerState scaffoldMessenger,
      String shopId,
      ) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: Colors.grey.shade300,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 左：検索ボタン
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                // TODO: 検索機能を実装
              },
            ),

            // 中央：赤い丸＋（新規追加）
            GestureDetector(
              onTap: () async {
                final newItem =
                await Navigator.of(context).push<SnackItem>(
                  MaterialPageRoute(
                    builder: (_) => const AddSnackFlowScreen(),
                  ),
                );

                if (newItem != null) {
                  // Firestore に在庫データを保存
                  try {
                    final user = FirebaseAuth.instance.currentUser;
                    await _db
                        .collection('shops')
                        .doc(shopId)
                        .collection('snacks')
                        .add({
                      'name': newItem.name,
                      'expiry': Timestamp.fromDate(newItem.expiry),
                      'janCode': newItem.janCode,
                      'price': newItem.price,
                      'createdAt': FieldValue.serverTimestamp(),
                      'createdByUserId': user?.uid,
                    });
                  } catch (e) {
                    if (!mounted) return;
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('在庫データの保存に失敗しました: $e'),
                      ),
                    );
                  }
                }
              },
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent,
                ),
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),

            // 右：フィルタボタン
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () {
                // TODO: フィルタ機能を実装
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Firestore ドキュメントIDと SnackItem をまとめて扱うための小さなクラス
class _SnackDocEntry {
  const _SnackDocEntry({
    required this.docId,
    required this.snack,
  });

  final String docId;
  final SnackItem snack;
}
