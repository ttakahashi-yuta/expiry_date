import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expiry_date/data/dummy_data.dart';
import 'package:expiry_date/models/snack_item.dart';
import 'package:expiry_date/screens/settings_screen.dart';
import 'package:expiry_date/core/settings/app_settings.dart';
import 'screens/add_snack_flow_screen.dart';
import 'package:expiry_date/screens/add_snack_flow_screen.dart';
import 'package:firebase_core/firebase_core.dart';
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

/// FirebaseAuth の状態に応じて
/// - 未ログイン: SignInScreen
/// - ログイン済み: 在庫一覧画面
/// を出し分けるゲート。
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          // 未ログイン → ログイン画面へ
          return const SignInScreen();
        } else {
          // ログイン済み → 在庫一覧画面へ
          //
          // ★ここがあなたの「今のメイン画面の Widget 名」にあたります。
          //   例：SnackListScreen / HomeScreen / InventoryScreen など。
          //   実際のクラス名に置き換えてください。
          return const HomeScreen();
        }
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
  late List<SnackItem> _snacks;
  final Map<String, String> _janNameCache = {};

  @override
  void initState() {
    super.initState();
    _snacks = List.from(dummySnacks);

    // 既存データからも、JANコードがあればキャッシュしておく（将来用）
    for (final snack in _snacks) {
      if (snack.janCode != null && snack.name.isNotEmpty) {
        _janNameCache[snack.janCode!] = snack.name;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    int expiredCount = 0;
    int soonCount = 0;
    int safeCount = 0;

    for (final snack in _snacks) {
      final daysLeft = snack.expiry.difference(now).inDays;
      if (daysLeft < 0) {
        expiredCount++;
      } else if (daysLeft <= 7) {
        soonCount++;
      } else {
        safeCount++;
      }
    }

    final List<SnackItem> sortedSnacks = List.from(_snacks)
      ..sort((a, b) => a.expiry.compareTo(b.expiry));

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
            onSelected: (value) {
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
            ],
          ),
          const SizedBox(width: 4),
        ],

      ),

      // =======================
      // メインリスト部分
      // =======================
      body: Column(
        children: [
          Padding(
            padding:
            const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatusIndicator(Icons.error, Colors.red, '期限切れ',
                    expiredCount),
                _buildStatusIndicator(
                    Icons.warning, Colors.amber, 'もうすぐ', soonCount),
                _buildStatusIndicator(
                    Icons.check_circle, Colors.green, '余裕あり', safeCount),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: sortedSnacks.length,
              itemBuilder: (context, index) {
                final snack = sortedSnacks[index];
                final daysLeft = snack.expiry.difference(now).inDays;
                final isExpired = daysLeft < 0;

                final Color backgroundColor;
                if (isExpired) {
                  backgroundColor = Colors.red.shade50;
                } else if (daysLeft <= 7) {
                  backgroundColor = Colors.amber.shade50;
                } else {
                  backgroundColor = Colors.green.shade50;
                }

                // ★ ここだけ Riverpod 化（UIはそのまま）
                final confirmDelete = ref.watch(confirmDeleteProvider);

                return Dismissible(
                  key: ValueKey(snack.name),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    color: Colors.red.shade400,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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
                        content: Text('「${snack.name}」を削除しますか？'),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(context).pop(false),
                            child: const Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.of(context).pop(true),
                            child: const Text('削除',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ) ??
                        false;
                  },
                  onDismissed: (direction) {
                    setState(() {
                      _snacks.remove(snack);
                    });

                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('「${snack.name}」を削除しました'),
                        action: SnackBarAction(
                          label: '元に戻す',
                          onPressed: () {
                            setState(() {
                              _snacks.add(snack);
                            });
                          },
                        ),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                  child: _buildSnackCard(snack, daysLeft, backgroundColor),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomActionBar(context),
    );
  }

  /// 駄菓子カードUI（★元のまま）
  Widget _buildSnackCard(SnackItem snack, int daysLeft, Color backgroundColor) {
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

  /// 状態アイコンバー（★元のまま）
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

  Widget _buildBottomActionBar(BuildContext context) {
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
                // 今は空のままでOK
              },
            ),

            // 中央：赤い丸＋（新規追加）
            GestureDetector(
              onTap: () async {
                final newItem = await Navigator.of(context).push<SnackItem>(
                  MaterialPageRoute(
                    builder: (_) => AddSnackFlowScreen(
                      janNameCache: _janNameCache,
                    ),
                  ),
                );

                if (newItem != null) {
                  setState(() {
                    _snacks.add(newItem);

                    if (newItem.janCode != null && newItem.name.isNotEmpty) {
                      _janNameCache[newItem.janCode!] = newItem.name;
                    }
                  });
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
                // （期限が近い順 / 期限切れのみ など）
              },
            ),
          ],
        ),
      ),
    );
  }

}
