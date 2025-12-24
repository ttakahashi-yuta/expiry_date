import 'package:flutter_riverpod/flutter_riverpod.dart';

/// アプリ内の設定（将来拡張用）。
///
/// 以前は「スワイプ削除時に確認ダイアログを出すか」を設定として持っていましたが、
/// 現在は「ゴミ箱（アーカイブ）方式」に移行したため、削除確認の設定は不要になりました。
///
/// ※既存コード互換のため、ConfirmDeleteNotifier / confirmDeleteProvider は残していますが
/// 　アプリ内では未使用（非表示）です。将来的に削除予定です。

@Deprecated('削除方式をゴミ箱（アーカイブ）に変更したため未使用です。')
class ConfirmDeleteNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;

  void toggle() => state = !state;
}

/// 互換維持のため残している Provider（現在は Settings 画面にも表示しない）。
@Deprecated('削除方式をゴミ箱（アーカイブ）に変更したため未使用です。')
final confirmDeleteProvider =
NotifierProvider<ConfirmDeleteNotifier, bool>(ConfirmDeleteNotifier.new);
