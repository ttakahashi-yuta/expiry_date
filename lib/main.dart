import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expiry_date/data/dummy_data.dart';
import 'package:expiry_date/models/snack_item.dart';
import 'package:expiry_date/screens/settings_screen.dart';
import 'package:expiry_date/core/settings/app_settings.dart';
import 'screens/add_snack_flow_screen.dart';
import 'package:expiry_date/screens/add_snack_flow_screen.dart';


void main() {
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
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
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
          IconButton(
            tooltip: '商品を追加',
            icon: const Icon(Icons.add_circle_outline, size: 28),
            onPressed: () async {
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
          ),
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
    );
  }

  /// 駄菓子カードUI（★元のまま）
  Widget _buildSnackCard(SnackItem snack, int daysLeft, Color backgroundColor) {
    final bool isExpired = daysLeft < 0;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 0.5),
          bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            margin: const EdgeInsets.only(right: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade400),
            ),
            child: const Icon(
              Icons.camera_alt_outlined,
              color: Colors.grey,
              size: 36,
            ),
          ),
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
                ),
                const SizedBox(height: 6),
                Text(
                  '賞味期限: ${snack.expiry.toLocal().toString().split(' ')[0]}',
                  style: const TextStyle(color: Colors.black87),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isExpired ? '期限切れ' : '残り${daysLeft}日',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
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
}
