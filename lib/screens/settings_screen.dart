import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:expiry_date/core/settings/app_settings.dart';
import 'package:expiry_date/screens/trash_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final soonThresholdDays = settings.soonThresholdDays;

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        // スクロール時の色付き防止（お好みで）
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          const _SectionHeader(title: '管理'),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('ゴミ箱'),
            subtitle: const Text('削除した在庫の復元・完全削除'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TrashScreen()),
              );
            },
          ),
          const Divider(height: 1),

          const SizedBox(height: 8),
          const _SectionHeader(title: '表示'),
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: const Text('「もうすぐ」判定日数'),
            subtitle: Text('賞味期限まで $soonThresholdDays 日以下を「もうすぐ」にします'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$soonThresholdDays日',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () async {
              // 関数に切り出さず、直接呼び出す形に整理
              await showDialog<void>(
                context: context,
                builder: (_) => _SoonThresholdDialog(currentDays: soonThresholdDays),
              );
            },
          ),
          const Divider(height: 1),

          const SizedBox(height: 8),
          const _SectionHeader(title: '情報'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('ライセンス'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: '賞味期限管理',
                // アプリのアイコンがある場合、ここにIconウィジェットを渡せます
                // applicationIcon: const Icon(Icons.inventory_2, size: 48),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SoonThresholdDialog extends ConsumerStatefulWidget {
  const _SoonThresholdDialog({
    required this.currentDays,
  });

  final int currentDays;

  @override
  ConsumerState<_SoonThresholdDialog> createState() => _SoonThresholdDialogState();
}

class _SoonThresholdDialogState extends ConsumerState<_SoonThresholdDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final text = widget.currentDays.toString();
    _controller = TextEditingController(text: text);

    // 【UX改善】開いた瞬間に数値を選択状態にする
    // これにより、ユーザーはバックスペースを押さずにすぐ新しい数値を入力できます
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _resetToDefault(BuildContext context) async {
    // ノティファイア側のメソッドを呼ぶ
    await ref.read(appSettingsProvider.notifier).resetSoonThresholdToDefault();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _save(BuildContext context) async {
    final text = _controller.text;

    // 空文字チェック
    if (text.isEmpty) {
      setState(() => _errorText = '数字を入力してください');
      return;
    }

    final parsed = int.tryParse(text);
    // digitsOnlyを使っているため、パースエラーは実質起きないが念のため
    if (parsed == null) {
      setState(() => _errorText = '無効な数値です');
      return;
    }

    // digitsOnlyなのでマイナス値チェックは不要
    if (parsed > 3650) {
      setState(() => _errorText = '大きすぎます（最大3650日）');
      return;
    }

    // 保存処理
    await ref.read(appSettingsProvider.notifier).setSoonThresholdDays(parsed);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('「もうすぐ」判定日数'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true, // 【UX改善】自動でキーボードを出す
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly, // 数字のみ許可
            ],
            decoration: InputDecoration(
              labelText: '日数',
              hintText: '例）30',
              helperText: '0以上の整数',
              errorText: _errorText,
              border: const OutlineInputBorder(), // 入力欄をわかりやすく
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onSubmitted: (_) => _save(context), // エンターキーで保存
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _resetToDefault(context),
          style: TextButton.styleFrom(foregroundColor: Colors.grey),
          child: const Text('デフォルトに戻す'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => _save(context),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), // 上のマージンを少し広げました
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith( // labelLargeの方がセクションヘッダらしい見た目になります
          color: theme.colorScheme.primary, // アクセントカラーを使用
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}