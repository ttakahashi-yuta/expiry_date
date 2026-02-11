import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:expiry_date/models/snack_item.dart';
import 'package:expiry_date/screens/settings_screen.dart';
import 'package:expiry_date/screens/add_snack_flow_screen.dart';
import 'package:expiry_date/core/user/user_providers.dart';
import 'package:expiry_date/core/user/user_repository.dart';
import 'package:expiry_date/core/settings/app_settings.dart';
import 'package:expiry_date/core/snacks/snack_repository.dart';
import 'package:expiry_date/screens/shop_selection_screen.dart';
import 'package:expiry_date/screens/edit_snack_screen.dart';
import 'package:expiry_date/screens/trash_screen.dart';
import 'package:expiry_date/core/notifications/notification_service.dart';
import 'package:expiry_date/core/notifications/badge_provider.dart'; // ★追加: バッジプロバイダーをインポート

import 'firebase_options.dart';
import 'core/auth/auth_repository.dart';
import 'screens/sign_in_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // 通知サービスのインスタンスを作って初期化
  final notificationService = NotificationService();
  await notificationService.init();
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
        final currentScale = media.textScaler.scale(1.0);
        final clampedScale = currentScale.clamp(_minTextScale, _maxTextScale);

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

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<User?>>(authStateChangesProvider, (previous, next) {
      final user = next.value;
      if (user != null && (previous == null || previous.value == null)) {
        ref.read(userRepositoryProvider).ensureUserDocument(user);
      }
    });

    final authState = ref.watch(authStateChangesProvider);
    final appUserAsync = ref.watch(appUserStreamProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const SignInScreen();

        return appUserAsync.when(
          data: (appUser) {
            if (appUser == null) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final currentShopId = appUser.currentShopId;
            if (currentShopId == null || currentShopId.isEmpty) {
              return const ShopSelectionScreen();
            }
            return const HomeScreen();
          },
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, stack) => Scaffold(body: Center(child: Text('エラー: $error'))),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(body: Center(child: Text('認証エラー: $error'))),
    );
  }
}

enum _SortKey {
  expiry,
  name,
  price,
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // 検索用の状態
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');

  // 並び替え状態
  _SortKey _sortKey = _SortKey.expiry;
  bool _sortAscending = true;
  final GlobalKey _sortButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 画面が表示されたら、iOS側に「通知（バッジ）を使ってもいいですか？」と聞く
    // これがないとiPhoneではバッジが出ません
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationServiceProvider).requestPermissions();
    });
  }


  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchQuery.dispose();
    super.dispose();
  }

  String _arrowMark(bool ascending) => ascending ? '▲' : '▼';

  String _sortKeyShortLabel(_SortKey key) {
    switch (key) {
      case _SortKey.expiry: return '期限';
      case _SortKey.name: return '名前';
      case _SortKey.price: return '売価';
    }
  }

  String _sortKeyMenuLabel(_SortKey key) {
    switch (key) {
      case _SortKey.expiry: return '期限順';
      case _SortKey.name: return '名前順';
      case _SortKey.price: return '売価順';
    }
  }

  String _currentSortTitleSuffix() {
    return '${_sortKeyShortLabel(_sortKey)}${_arrowMark(_sortAscending)}';
  }

  void _applySortSelection(_SortKey key) {
    if (!mounted) return;
    setState(() {
      if (_sortKey == key) {
        _sortAscending = !_sortAscending;
      } else {
        _sortKey = key;
        _sortAscending = true;
      }
    });
  }

  void _sortSnackItems(List<SnackItem> items) {
    int compareByName(SnackItem a, SnackItem b) {
      final an = a.name.trim().toLowerCase();
      final bn = b.name.trim().toLowerCase();
      final c = an.compareTo(bn);
      if (c != 0) return c;
      final ce = a.expiry.compareTo(b.expiry);
      if (ce != 0) return ce;
      return (a.id ?? '').compareTo(b.id ?? '');
    }

    int compareByExpiry(SnackItem a, SnackItem b) {
      final c = a.expiry.compareTo(b.expiry);
      if (c != 0) return c;
      return compareByName(a, b);
    }

    int compareByPrice(SnackItem a, SnackItem b) {
      final ap = a.price;
      final bp = b.price;

      if (ap == null && bp == null) return compareByName(a, b);
      if (ap == null) return 1;
      if (bp == null) return -1;

      final c = ap.compareTo(bp);
      if (c != 0) return c;
      return compareByName(a, b);
    }

    int baseCompare(SnackItem a, SnackItem b) {
      switch (_sortKey) {
        case _SortKey.expiry: return compareByExpiry(a, b);
        case _SortKey.name: return compareByName(a, b);
        case _SortKey.price: return compareByPrice(a, b);
      }
    }

    items.sort((a, b) {
      final c = baseCompare(a, b);
      if (_sortKey == _SortKey.price) {
        final ap = a.price;
        final bp = b.price;
        if (ap == null || bp == null) return c;
      }
      return _sortAscending ? c : -c;
    });
  }

  Future<void> _openSortPopup(BuildContext context) async {
    final keyContext = _sortButtonKey.currentContext;
    if (keyContext == null) return;

    final renderObject = keyContext.findRenderObject();
    if (renderObject is! RenderBox) return;

    final box = renderObject;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;

    const double menuWidth = 220;
    const double itemHeight = 48;
    const double menuVPadding = 6;
    const double menuGap = 8;
    const double edgeMargin = 8;
    final double menuHeight = (menuVPadding * 2) + (itemHeight * 3);

    double left = (pos.dx + size.width) - menuWidth;
    left = left.clamp(edgeMargin, screenSize.width - menuWidth - edgeMargin);
    double top = pos.dy - menuHeight - menuGap;
    if (top < topPadding + edgeMargin) top = pos.dy + size.height + menuGap;
    if (top + menuHeight > screenSize.height - edgeMargin) {
      top = screenSize.height - menuHeight - edgeMargin;
      if (top < topPadding + edgeMargin) top = topPadding + edgeMargin;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'sort_menu',
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, anim1, anim2) {
        var localKey = _sortKey;
        var localAsc = _sortAscending;

        Widget buildTile({required _SortKey key, required IconData icon}) {
          final selected = localKey == key;
          final shownArrow = selected ? _arrowMark(localAsc) : _arrowMark(true);
          return InkWell(
            onTap: () {
              if (selected) {
                localAsc = !localAsc;
              } else {
                localKey = key;
                localAsc = true;
              }
              _applySortSelection(key);
              (ctx as Element).markNeedsBuild();
            },
            child: SizedBox(
              height: itemHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_sortKeyMenuLabel(key), style: const TextStyle(fontSize: 15)),
                    ),
                    Text(shownArrow, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    if (selected) const Icon(Icons.check, size: 18),
                  ],
                ),
              ),
            ),
          );
        }

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: menuVPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      buildTile(key: _SortKey.expiry, icon: Icons.event_outlined),
                      buildTile(key: _SortKey.name, icon: Icons.sort_by_alpha),
                      buildTile(key: _SortKey.price, icon: Icons.payments_outlined),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (ctx, anim, sec, child) {
        return FadeTransition(opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut), child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // ★追加: ここで badgeProvider を watch することでバッジ更新が有効になります
    ref.watch(badgeProvider);

    final now = DateTime.now();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final soonThresholdDays = ref.watch(appSettingsProvider).soonThresholdDays;

    final snacksAsync = ref.watch(snackListStreamProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: Text(
          '在庫一覧（${_currentSortTitleSuffix()}）',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'shop':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopSelectionScreen()));
                  break;
                case 'settings':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  break;
                case 'trash':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrashScreen()));
                  break;
                case 'help': break;
                case 'about': break;
                case 'logout':
                  await ref.read(authRepositoryProvider).signOut();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'shop', child: Text('店舗')),
              PopupMenuItem(value: 'settings', child: Text('設定')),
              PopupMenuItem(value: 'trash', child: Text('ゴミ箱')),
              PopupMenuItem(value: 'help', child: Text('ヘルプ')),
              PopupMenuItem(value: 'about', child: Text('このアプリについて')),
              PopupMenuItem(value: 'logout', child: Text('ログアウト')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: snacksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('エラーが発生しました: $err')),
          data: (allSnacks) {
            return ValueListenableBuilder<String>(
              valueListenable: _searchQuery,
              builder: (context, searchText, _) {
                final query = searchText.trim();
                List<SnackItem> filteredList;

                if (query.isEmpty) {
                  filteredList = List.of(allSnacks);
                } else {
                  final lower = query.toLowerCase();
                  filteredList = allSnacks.where((s) {
                    return s.name.toLowerCase().contains(lower);
                  }).toList();
                }

                _sortSnackItems(filteredList);

                int expiredCount = 0;
                int soonCount = 0;
                int safeCount = 0;

                for (final s in filteredList) {
                  final daysLeft = s.expiry.difference(now).inDays;
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
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatusIndicator(Icons.error, Colors.red, '超過', expiredCount > 999 ? '999+' : '$expiredCount'),
                          _buildStatusIndicator(Icons.warning, Colors.amber, 'もうすぐ', soonCount > 999 ? '999+' : '$soonCount'),
                          _buildStatusIndicator(Icons.check_circle, Colors.green, '', safeCount > 999 ? '999+' : '$safeCount'),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: filteredList.isEmpty
                          ? Center(
                        child: Text(
                          query.isEmpty
                              ? 'まだ在庫が登録されていません。\n下の＋ボタンから追加してください。'
                              : '該当する在庫がありません。',
                          textAlign: TextAlign.center,
                        ),
                      )
                          : ListView.builder(
                        itemCount: filteredList.length,
                        itemBuilder: (context, index) {
                          final snack = filteredList[index];
                          final docId = snack.id!;
                          final daysLeft = snack.expiry.difference(now).inDays;
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
                            key: ValueKey(docId),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              color: Colors.red.shade400,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: const Icon(Icons.delete_outline, color: Colors.white, size: 30),
                            ),
                            onDismissed: (direction) async {
                              final repo = ref.read(snackRepositoryProvider);
                              try {
                                await repo.archiveSnack(docId);

                                if (!mounted) return;
                                scaffoldMessenger.clearSnackBars();
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    margin: const EdgeInsets.all(12),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    content: Text('ゴミ箱に移動: ${snack.name}', maxLines: 1),
                                    action: SnackBarAction(
                                      label: '元に戻す',
                                      onPressed: () async {
                                        try {
                                          await repo.restoreSnack(docId);
                                        } catch (e) {
                                          if (!mounted) return;
                                          scaffoldMessenger.showSnackBar(SnackBar(content: Text('元に戻せませんでした: $e')));
                                        }
                                      },
                                    ),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                scaffoldMessenger.showSnackBar(SnackBar(content: Text('ゴミ箱への移動に失敗しました: $e')));
                              }
                            },
                            child: InkWell(
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EditSnackScreen(
                                      docId: docId,
                                      snack: snack,
                                    ),
                                  ),
                                );
                              },
                              child: _buildSnackCard(snack, daysLeft, backgroundColor),
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
      bottomNavigationBar: _buildBottomSection(context, scaffoldMessenger),
    );
  }

  // _buildSnackCard, _buildStatusIndicator, _buildBottomSection, _buildBottomActionBar は変更なしのため省略しません（念のためそのまま記述しています）

  Widget _buildSnackCard(SnackItem snack, int daysLeft, Color backgroundColor) {
    final bool isExpired = daysLeft < 0;
    final String expiryText = snack.expiry.toLocal().toString().split(' ')[0];
    final hsl = HSLColor.fromColor(backgroundColor);
    final Color boxBorderColor = hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor();

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
          Container(
            width: 80,
            height: 72,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: boxBorderColor, width: 1.2),
            ),
            child: Center(
              child: isExpired
                  ? const Text('期限切れ', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black))
                  : FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('残り', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black)),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: mainNumberText, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black)),
                          TextSpan(text: unitText, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black)),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(snack.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: Text('賞味期限: $expiryText', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87), maxLines: 1)),
                    const SizedBox(width: 8),
                    Text(snack.price != null ? '${snack.price}円' : '未設定', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87), textAlign: TextAlign.right),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(IconData icon, Color color, String label, String countText) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 4),
        Text(countText, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }

  Widget _buildBottomSection(BuildContext context, ScaffoldMessengerState scaffoldMessenger) {
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        setState(() => _isSearching = false);
                        FocusScope.of(context).unfocus();
                      },
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => _searchQuery.value = value,
                ),
              ),
            _buildBottomActionBar(context, scaffoldMessenger),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(BuildContext context, ScaffoldMessengerState scaffoldMessenger) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              if (_isSearching) {
                if (_searchController.text.trim().isEmpty) {
                  setState(() => _isSearching = false);
                  FocusScope.of(context).unfocus();
                } else {
                  FocusScope.of(context).requestFocus(_searchFocusNode);
                }
              } else {
                setState(() => _isSearching = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  FocusScope.of(context).requestFocus(_searchFocusNode);
                });
              }
            },
          ),
          GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddSnackFlowScreen()),
              );
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent),
              child: const Icon(Icons.add, color: Colors.white, size: 30),
            ),
          ),
          IconButton(
            key: _sortButtonKey,
            onPressed: () => _openSortPopup(context),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.sort),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300, width: 0.8),
                    ),
                    child: Text(_arrowMark(_sortAscending), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}