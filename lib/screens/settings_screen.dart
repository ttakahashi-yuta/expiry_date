import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expiry_date/core/settings/app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(confirmDeleteProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          _buildSectionHeader('一般設定'),
          SwitchListTile(
            title: const Text('削除時に確認ダイアログを表示する'),
            subtitle: const Text('OFFにするとスワイプですぐ削除されます（Undoは有効）'),
            value: value,
            onChanged: (v) => ref.read(confirmDeleteProvider.notifier).set(v),
          ),
          const Divider(),
          _buildSectionHeader('その他'),
          ListTile(
            title: const Text('アプリ情報'),
            subtitle: const Text('バージョンや開発者情報'),
            trailing: const Icon(Icons.info_outline),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }
}
