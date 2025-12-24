import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:expiry_date/screens/trash_screen.dart';

/// 設定画面
///
/// 以前は「スワイプ削除時に確認ダイアログを表示する」設定がありましたが、
/// 現在は削除フローが「ゴミ箱（アーカイブ）方式」に変更されたため不要になりました。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _SectionHeader(title: '管理'),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('ゴミ箱を見る'),
            subtitle: const Text('削除した商品を確認・復元・完全削除できます'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TrashScreen()),
              );
            },
          ),
          const Divider(height: 1),

          const SizedBox(height: 8),
          _SectionHeader(title: '情報'),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('ライセンス'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: '賞味期限管理',
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
