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
            onTap: () => _showSoonThresholdDialog(
              context: context,
              currentDays: soonThresholdDays,
            ),
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
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<void> _showSoonThresholdDialog({
  required BuildContext context,
  required int currentDays,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _SoonThresholdDialog(currentDays: currentDays),
  );
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
    _controller = TextEditingController(text: widget.currentDays.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _resetToDefault(BuildContext context) async {
    await ref.read(appSettingsProvider.notifier).resetSoonThresholdToDefault();
    if (!mounted) return;

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  Future<void> _save(BuildContext context) async {
    final parsed = int.tryParse(_controller.text);

    if (parsed == null) {
      setState(() {
        _errorText = '数字を入力してください';
      });
      return;
    }

    if (parsed > 3650) {
      setState(() {
        _errorText = '大きすぎます（最大3650日）';
      });
      return;
    }

    if (parsed < 0) {
      setState(() {
        _errorText = '0以上を入力してください';
      });
      return;
    }

    await ref.read(appSettingsProvider.notifier).setSoonThresholdDays(parsed);
    if (!mounted) return;

    FocusScope.of(context).unfocus();
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
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: '日数',
              helperText: '0以上の整数（デフォルト: 30）',
              errorText: _errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _resetToDefault(context),
          child: const Text('デフォルトに戻す'),
        ),
        TextButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop();
          },
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
