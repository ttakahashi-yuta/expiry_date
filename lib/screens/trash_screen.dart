import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:expiry_date/core/user/user_providers.dart';
import 'package:expiry_date/models/snack_item.dart';

/// ゴミ箱画面
///
/// - 一覧は isArchived == true のみ表示
/// - 左スワイプ（endToStart）：完全削除（Firestoreから削除）
/// - 右スワイプ（startToEnd）：元に戻す（isArchived=false）
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopId = ref.watch(currentShopIdProvider);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final db = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ゴミ箱'),
        actions: [
          IconButton(
            tooltip: 'ゴミ箱を空にする',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('ゴミ箱を空にする'),
                  content: const Text('ゴミ箱の中身をすべて完全削除します。よろしいですか？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('キャンセル'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text(
                        '削除',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ) ??
                  false;

              if (!ok) return;

              try {
                final snapshot = await db
                    .collection('shops')
                    .doc(shopId)
                    .collection('snacks')
                    .where('isArchived', isEqualTo: true)
                    .get();

                final batch = db.batch();
                for (final doc in snapshot.docs) {
                  batch.delete(doc.reference);
                }
                await batch.commit();

                scaffoldMessenger.clearSnackBars();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('ゴミ箱を空にしました')),
                );
              } catch (e) {
                scaffoldMessenger.clearSnackBars();
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('ゴミ箱を空にできませんでした: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db
            .collection('shops')
            .doc(shopId)
            .collection('snacks')
            .where('isArchived', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('ゴミ箱の取得中にエラーが発生しました: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

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

            return _TrashDocEntry(
              docId: doc.id,
              snack: snack,
            );
          }).toList();

          entries.sort((a, b) => a.snack.expiry.compareTo(b.snack.expiry));

          if (entries.isEmpty) {
            return const Center(
              child: Text('ゴミ箱は空です。'),
            );
          }

          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final snack = entry.snack;

              return Dismissible(
                key: ValueKey('trash_${entry.docId}'),
                direction: DismissDirection.horizontal,

                // 右へスワイプ → 復元（startToEnd）
                background: Container(
                  alignment: Alignment.centerLeft,
                  color: Colors.green.shade400,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Row(
                    children: [
                      Icon(Icons.undo, color: Colors.white, size: 28),
                      SizedBox(width: 8),
                      Text(
                        '元に戻す',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // 左へスワイプ → 完全削除（endToStart）
                secondaryBackground: Container(
                  alignment: Alignment.centerRight,
                  color: Colors.red.shade400,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '完全削除',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.delete_forever, color: Colors.white, size: 28),
                    ],
                  ),
                ),

                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.endToStart) {
                    // 完全削除は確認
                    return await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('完全削除の確認'),
                        content: Text('「${snack.name}」を完全に削除しますか？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text(
                              '削除',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ) ??
                        false;
                  }
                  // 復元は確認なし
                  return true;
                },

                onDismissed: (direction) async {
                  try {
                    final user = FirebaseAuth.instance.currentUser;

                    if (direction == DismissDirection.startToEnd) {
                      // 復元
                      await db
                          .collection('shops')
                          .doc(shopId)
                          .collection('snacks')
                          .doc(entry.docId)
                          .update({
                        'isArchived': false,
                        'archivedAt': null,
                        'archivedByUserId': null,
                        'updatedAt': FieldValue.serverTimestamp(),
                        'updatedByUserId': user?.uid,
                      });

                      scaffoldMessenger.clearSnackBars();
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('「${snack.name}」を元に戻しました'),
                          action: SnackBarAction(
                            label: '元に戻す',
                            onPressed: () async {
                              await db
                                  .collection('shops')
                                  .doc(shopId)
                                  .collection('snacks')
                                  .doc(entry.docId)
                                  .update({
                                'isArchived': true,
                                'archivedAt': FieldValue.serverTimestamp(),
                                'archivedByUserId': user?.uid,
                                'updatedAt': FieldValue.serverTimestamp(),
                                'updatedByUserId': user?.uid,
                              });
                            },
                          ),
                        ),
                      );
                    } else {
                      // 完全削除
                      await db
                          .collection('shops')
                          .doc(shopId)
                          .collection('snacks')
                          .doc(entry.docId)
                          .delete();

                      scaffoldMessenger.clearSnackBars();
                      scaffoldMessenger.showSnackBar(
                        SnackBar(content: Text('「${snack.name}」を完全削除しました')),
                      );
                    }
                  } catch (e) {
                    scaffoldMessenger.clearSnackBars();
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text('操作に失敗しました: $e')),
                    );
                  }
                },

                child: ListTile(
                  title: Text(
                    snack.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '賞味期限: ${snack.expiry.toLocal().toString().split(' ')[0]}'
                        '${snack.price != null ? ' / ${snack.price}円' : ''}',
                  ),
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

/// Firestore ドキュメントIDと SnackItem をまとめて扱うための小さなクラス（ゴミ箱用）
class _TrashDocEntry {
  const _TrashDocEntry({
    required this.docId,
    required this.snack,
  });

  final String docId;
  final SnackItem snack;
}
