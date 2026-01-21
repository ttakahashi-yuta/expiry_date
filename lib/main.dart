import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:expiry_date/models/snack_item.dart';
import 'package:expiry_date/screens/settings_screen.dart';
import 'package:expiry_date/screens/add_snack_flow_screen.dart';
import 'package:expiry_date/core/user/user_providers.dart';
import 'package:expiry_date/core/user/user_repository.dart';
import 'package:expiry_date/core/settings/app_settings.dart';
import 'package:expiry_date/screens/shop_selection_screen.dart';
import 'package:expiry_date/screens/edit_snack_screen.dart';
import 'package:expiry_date/screens/trash_screen.dart';

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

  static const double _minTextScale = 0.90;
  static const double _maxTextScale = 1.00;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '賞味期限管理',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.orange,
      ),

      builder: (context, child) {
        final media = MediaQuery.of(context);

        // 現在のスケールを TextScaler 経由で取得
        final currentScale = media.textScaler.scale(1.0);

        // 上限・下限を適用
        final clampedScale = currentScale.clamp(
          _minTextScale,
          _maxTextScale,
        );

        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(clampedScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },

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

  // 検索用の状態
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');

  // =======================
  // Flicker対策：Streamの再生成を止める
  // =======================
  String? _snacksStreamShopId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _snacksStream;
  QuerySnapshot<Map<String, dynamic>>? _lastSnacksSnapshot;

  Stream<QuerySnapshot<Map<String, dynamic>>> _getSnacksStream(String shopId) {
    if (_snacksStream == null || _snacksStreamShopId != shopId) {
      _snacksStreamShopId = shopId;
      _snacksStream = _db
          .collection('shops')
          .doc(shopId)
          .collection('snacks')
          .snapshots();
    }
    return _snacksStream!;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final shopId = ref.watch(currentShopIdProvider);
    final soonThresholdDays = ref.watch(appSettingsProvider).soonThresholdDays;

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
                case 'shop':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ShopSelectionScreen()),
                  );
                  break;
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  break;
                case 'trash':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TrashScreen()),
                  );
                  break;
                case 'help':
                // TODO: ヘルプ画面
                  break;
                case 'about':
                // TODO: このアプリについて
                  break;
                case 'logout':
                  final authRepo = ref.read(authRepositoryProvider);
                  await authRepo.signOut();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'shop',
                child: Text('店舗'),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Text('設定'),
              ),
              PopupMenuItem(
                value: 'trash',
                child: Text('ゴミ箱'),
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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // 画面のどこかをタップしたらキーボードだけ閉じる
          FocusScope.of(context).unfocus();
        },
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _getSnacksStream(shopId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('在庫の取得中にエラーが発生しました: ${snapshot.error}'),
              );
            }

            // データが取れたら保持しておく（次のrebuildでwaitingになっても表示を維持する）
            if (snapshot.hasData) {
              _lastSnacksSnapshot = snapshot.data;
            }

            // waitingでも、直前データがあればそれを表示して全画面ローディングにしない
            final effectiveSnapshot = snapshot.data ?? _lastSnacksSnapshot;

            if (effectiveSnapshot == null) {
              // 初回だけローディング
              return const Center(child: CircularProgressIndicator());
            }

            final docs = effectiveSnapshot.docs;

            // isArchived が true のもの（ゴミ箱行き）は通常一覧では非表示。
            // 過去データで isArchived が未設定(null/フィールド無し)の場合は未アーカイブ扱いで表示する。
            final visibleDocs = docs.where((doc) {
              final data = doc.data();
              return data['isArchived'] != true;
            }).toList();

            // Firestore のドキュメントから SnackItem のリストを作成（全件）
            final allEntries = visibleDocs.map((doc) {
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

            // 賞味期限順にソート（元リスト）
            allEntries.sort(
                  (a, b) => a.snack.expiry.compareTo(b.snack.expiry),
            );

            // 検索クエリだけをトリガーに、リスト部分だけを再ビルド
            return ValueListenableBuilder<String>(
              valueListenable: _searchQuery,
              builder: (context, searchText, _) {
                final query = searchText.trim();

                // 検索文字列でフィルタ（部分一致）
                final List<_SnackDocEntry> filteredEntries;
                if (query.isEmpty) {
                  filteredEntries = allEntries;
                } else {
                  final lower = query.toLowerCase();
                  filteredEntries = allEntries.where((entry) {
                    final name = entry.snack.name.toLowerCase();
                    return name.contains(lower);
                  }).toList();
                }

                // ステータス別カウント（表示中のリストに対して）
                int expiredCount = 0;
                int soonCount = 0;
                int safeCount = 0;

                for (final entry in filteredEntries) {
                  final daysLeft = entry.snack.expiry.difference(now).inDays;
                  if (daysLeft < 0) {
                    expiredCount++;
                  } else if (daysLeft <= soonThresholdDays) {
                    soonCount++;
                  } else {
                    safeCount++;
                  }
                }

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
                            Icons.error,
                            Colors.red,
                            '超過',
                            expiredCount > 999 ? '999+' : '$expiredCount', // 文字列として渡す
                          ),
                          _buildStatusIndicator(
                            Icons.warning,
                            Colors.amber,
                            'もうすぐ',
                            soonCount > 999 ? '999+' : '$soonCount', // 文字列として渡す
                          ),
                          _buildStatusIndicator(
                            Icons.check_circle,
                            Colors.green,
                            '',
                            safeCount > 999 ? '999+' : '$safeCount', // 文字列として渡す
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: filteredEntries.isEmpty
                          ? Center(
                        child: Text(
                          query.isEmpty
                              ? 'まだ在庫が登録されていません。\n下の＋ボタンから追加してください。'
                              : '該当する在庫がありません。',
                          textAlign: TextAlign.center,
                        ),
                      )
                          : ListView.builder(
                        itemCount: filteredEntries.length,
                        itemBuilder: (context, index) {
                          final entry = filteredEntries[index];
                          final snack = entry.snack;
                          final daysLeft =
                              snack.expiry.difference(now).inDays;
                          final isExpired = daysLeft < 0;

                          final Color backgroundColor;
                          if (isExpired) {
                            backgroundColor = Colors.red.shade50;
                          } else if (daysLeft <= soonThresholdDays) {
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: const Icon(
                                Icons.delete_outline,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                            onDismissed: (direction) async {
                              try {
                                final user =
                                    FirebaseAuth.instance.currentUser;
                                await _db
                                    .collection('shops')
                                    .doc(shopId)
                                    .collection('snacks')
                                    .doc(entry.docId)
                                    .update({
                                  'isArchived': true,
                                  'archivedAt':
                                  FieldValue.serverTimestamp(),
                                  'archivedByUserId': user?.uid,
                                  'updatedAt':
                                  FieldValue.serverTimestamp(),
                                  'updatedByUserId': user?.uid,
                                });

                                if (!mounted) return;
                                scaffoldMessenger.clearSnackBars();
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    margin: const EdgeInsets.all(12),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    content: Text(
                                      'ゴミ箱に移動: ${snack.name}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                    ),
                                    action: SnackBarAction(
                                      label: '元に戻す',
                                      onPressed: () async {
                                        try {
                                          final currentUser =
                                              FirebaseAuth.instance
                                                  .currentUser;
                                          await _db
                                              .collection('shops')
                                              .doc(shopId)
                                              .collection('snacks')
                                              .doc(entry.docId)
                                              .update({
                                            'isArchived': false,
                                            'archivedAt': null,
                                            'archivedByUserId': null,
                                            'updatedAt': FieldValue
                                                .serverTimestamp(),
                                            'updatedByUserId':
                                            currentUser?.uid,
                                          });
                                        } catch (e) {
                                          if (!mounted) return;
                                          scaffoldMessenger
                                              .clearSnackBars();
                                          scaffoldMessenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '元に戻せませんでした: $e',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                    duration:
                                    const Duration(seconds: 3),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                scaffoldMessenger.clearSnackBars();
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'ゴミ箱への移動に失敗しました: $e',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: InkWell(
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EditSnackScreen(
                                      docId: entry.docId,
                                      snack: snack,
                                    ),
                                  ),
                                );
                              },
                              child: _buildSnackCard(
                                snack,
                                daysLeft,
                                backgroundColor,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),

      // 検索バー + フッター（キーボード表示時はまとめてキーボードの上に来る）
      bottomNavigationBar: _buildBottomSection(
        context,
        scaffoldMessenger,
        shopId,
      ),
    );
  }

  /// 駄菓子カードUI
  Widget _buildSnackCard(SnackItem snack, int daysLeft, Color backgroundColor) {
    final bool isExpired = daysLeft < 0;
    final String expiryText =
    snack.expiry.toLocal().toString().split(' ')[0]; // yyyy-MM-dd 部分だけ

    // 左ボックス用：背景色と同系色で少し濃い枠線色を計算
    final hsl = HSLColor.fromColor(backgroundColor);
    final Color boxBorderColor = hsl
        .withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0))
        .toColor();

    // 残り日数の表示ロジック
    // 2年以上先なら「残り◯年」と年単位、それ以外は「残り◯日」
    final int absDays = daysLeft.abs();
    String mainNumberText;
    String unitText;

    if (!isExpired && absDays >= 365 * 2) {
      final years = (absDays / 365).floor();
      mainNumberText = years.toString();
      unitText = '年';
    } else {
      mainNumberText = daysLeft.toString();
      unitText = '日';
    }

    return Container(
      decoration: BoxDecoration(
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
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: boxBorderColor,
                width: 1.2,
              ),
            ),
            child: Center(
              child: isExpired
                  ? const Text(
                '期限切れ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14, // 16から少し下げるとより安全です
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              )
                  : FittedBox(
                // ← 追加：中身がはみ出そうな場合に自動で縮小させる
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min, // ← 追加：必要最小限のサイズに
                  children: [
                    const Text(
                      '残り',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: mainNumberText,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          TextSpan(
                            text: unitText,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
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
          ),

          // 右側：商品名 / （賞味期限 ＋ 売価）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '賞味期限: $expiryText',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      snack.price != null ? '${snack.price}円' : '未設定',
                      style: const TextStyle(
                        fontSize: 16,
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
      IconData icon,
      Color color,
      String label,
      String countText, // ← int count から String countText に変更
      ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 4),
        Text(
          countText, // ← $count から countText に変更
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

  /// 検索バー + フッターをまとめて構築
  Widget _buildBottomSection(
      BuildContext context,
      ScaffoldMessengerState scaffoldMessenger,
      String shopId,
      ) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isSearching)
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: '商品名で検索',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _searchQuery.value = '';
                        setState(() {
                          _isSearching = false;
                        });
                        FocusScope.of(context).unfocus();
                      },
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    // 画面全体の setState は行わず、
                    // 検索クエリだけを更新してリスト部分だけ再ビルドさせる
                    _searchQuery.value = value;
                  },
                ),
              ),
            _buildBottomActionBar(context, scaffoldMessenger, shopId),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(
      BuildContext context,
      ScaffoldMessengerState scaffoldMessenger,
      String shopId,
      ) {
    return Container(
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
              if (_isSearching) {
                // 既に検索窓が開いている → 入力が空なら閉じる
                if (_searchController.text.trim().isEmpty) {
                  setState(() {
                    _isSearching = false;
                  });
                  FocusScope.of(context).unfocus();
                } else {
                  // 入力がある間は閉じない → フォーカスだけ当て直す
                  FocusScope.of(context).requestFocus(_searchFocusNode);
                }
              } else {
                // 検索窓を開いてフォーカス＆キーボード表示
                setState(() {
                  _isSearching = true;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  FocusScope.of(context).requestFocus(_searchFocusNode);
                });
              }
            },
          ),

          // 中央：赤い丸＋（新規追加）
          GestureDetector(
            onTap: () async {
              final newItem = await Navigator.of(context).push<SnackItem>(
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
                    'isArchived': false,
                    'createdAt': FieldValue.serverTimestamp(),
                    'createdByUserId': user?.uid,
                    'updatedAt': FieldValue.serverTimestamp(),
                    'updatedByUserId': user?.uid,
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
