import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:expiry_date/core/snacks/snack_repository.dart';
import 'package:expiry_date/models/snack_item.dart';

/// ゴミ箱画面
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedSnacksAsync = ref.watch(archivedSnackListStreamProvider);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ゴミ箱'),
        // ★修正点: スクロール時に色がつくのを防ぐ設定
        scrolledUnderElevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: [
          IconButton(
            tooltip: 'ゴミ箱を空にする',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('ゴミ箱を空にする'),
                  content: const Text('ゴミ箱の中身をすべて完全削除します。\nこの操作は取り消せません。\nよろしいですか？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('キャンセル'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('削除', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ) ?? false;

              if (!ok) return;

              try {
                final currentList = archivedSnacksAsync.value ?? [];
                if (currentList.isEmpty) {
                  scaffoldMessenger.showSnackBar(const SnackBar(content: Text('ゴミ箱はすでに空です')));
                  return;
                }

                final repo = ref.read(snackRepositoryProvider);
                int count = 0;
                for (final item in currentList) {
                  if (item.id != null) {
                    await repo.deleteSnackPermanently(item.id!);
                    count++;
                  }
                }

                scaffoldMessenger.showSnackBar(SnackBar(content: Text('$count 件を完全に削除しました')));
              } catch (e) {
                scaffoldMessenger.showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
              }
            },
          ),
        ],
      ),
      body: archivedSnacksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('エラーが発生しました: $err')),
        data: (snacks) {
          if (snacks.isEmpty) {
            return const Center(child: Text('ゴミ箱は空です。'));
          }

          return ListView.builder(
            itemCount: snacks.length,
            itemBuilder: (context, index) {
              final snack = snacks[index];
              final docId = snack.id!;

              return Dismissible(
                key: ValueKey('trash_$docId'),
                direction: DismissDirection.horizontal,

                // 右へスワイプ → 復元
                background: Container(
                  alignment: Alignment.centerLeft,
                  color: Colors.green.shade400,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Row(
                    children: [
                      Icon(Icons.undo, color: Colors.white, size: 28),
                      SizedBox(width: 8),
                      Text('元に戻す', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),

                // 左へスワイプ → 完全削除
                secondaryBackground: Container(
                  alignment: Alignment.centerRight,
                  color: Colors.red.shade400,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('完全削除', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      SizedBox(width: 8),
                      Icon(Icons.delete_forever, color: Colors.white, size: 28),
                    ],
                  ),
                ),

                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.endToStart) {
                    return await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('完全削除の確認'),
                        content: Text('「${snack.name}」を完全に削除しますか？\n元に戻すことはできません。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('削除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ) ?? false;
                  }
                  return true;
                },

                onDismissed: (direction) async {
                  final repo = ref.read(snackRepositoryProvider);
                  try {
                    if (direction == DismissDirection.startToEnd) {
                      await repo.restoreSnack(docId);
                      scaffoldMessenger.clearSnackBars();
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('「${snack.name}」を元に戻しました'),
                          action: SnackBarAction(
                            label: '取り消す',
                            onPressed: () async {
                              await repo.archiveSnack(docId);
                            },
                          ),
                        ),
                      );
                    } else {
                      await repo.deleteSnackPermanently(docId);
                      scaffoldMessenger.clearSnackBars();
                      scaffoldMessenger.showSnackBar(
                        SnackBar(content: Text('「${snack.name}」を完全削除しました')),
                      );
                    }
                  } catch (e) {
                    scaffoldMessenger.showSnackBar(SnackBar(content: Text('操作に失敗しました: $e')));
                  }
                },

                child: ListTile(
                  title: Text(
                    snack.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    // ★修正: 打ち消し線を削除、色はグレーのまま
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '賞味期限: ${snack.expiry.toLocal().toString().split(' ')[0]}'
                        '${snack.price != null ? ' / ${snack.price}円' : ''}',
                  ),
                  // ★修正: アイコンの色指定を削除してデフォルトに戻す
                  leading: const Icon(Icons.delete_outline),
                ),
              );
            },
          );
        },
      ),
    );
  }
}