import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 削除確認ON/OFFを管理する（初期値: true）
class ConfirmDeleteNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
  void toggle() => state = !state;
}

/// Riverpod 3.x の NotifierProvider
final confirmDeleteProvider =
NotifierProvider<ConfirmDeleteNotifier, bool>(ConfirmDeleteNotifier.new);
