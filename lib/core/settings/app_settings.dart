import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    required this.soonThresholdDays,
    required this.isKeepAddingEnabled, // ★追加
  });

  /// 「もうすぐ」判定（daysLeft <= soonThresholdDays で “もうすぐ”）
  final int soonThresholdDays;

  /// 連続登録チェックボックスの状態
  final bool isKeepAddingEnabled; // ★追加

  static const int defaultSoonThresholdDays = 30;
  static const int maxSoonThresholdDays = 3650; // 10年

  AppSettings copyWith({
    int? soonThresholdDays,
    bool? isKeepAddingEnabled,
  }) {
    return AppSettings(
      soonThresholdDays: soonThresholdDays ?? this.soonThresholdDays,
      isKeepAddingEnabled: isKeepAddingEnabled ?? this.isKeepAddingEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.soonThresholdDays == soonThresholdDays &&
        other.isKeepAddingEnabled == isKeepAddingEnabled;
  }

  @override
  int get hashCode => Object.hash(soonThresholdDays, isKeepAddingEnabled);
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const String _keySoonThresholdDays = 'soonThresholdDays';
  static const String _keyKeepAdding = 'keepAddingEnabled'; // ★キー追加

  @override
  AppSettings build() {
    // ★ build中は state が未初期化の瞬間があるので、非同期ロードは build の外へ
    Future.microtask(_loadFromPrefs);

    return const AppSettings(
      soonThresholdDays: AppSettings.defaultSoonThresholdDays,
      isKeepAddingEnabled: false, // デフォルト値
    );
  }

  Future<void> _loadFromPrefs() async {
    final before = state;
    final prefs = await SharedPreferences.getInstance();

    // 読み込み
    final savedDays = prefs.getInt(_keySoonThresholdDays);
    final savedKeepAdding = prefs.getBool(_keyKeepAdding);

    if (!ref.mounted) return;
    // ユーザー操作などで state が変わっていたら、読み込み結果で上書きしない
    if (state != before) return;

    // 更新
    state = state.copyWith(
      soonThresholdDays: savedDays != null ? _clampSoonDays(savedDays) : null,
      isKeepAddingEnabled: savedKeepAdding,
    );
  }

  Future<void> setSoonThresholdDays(int days) async {
    final clamped = _clampSoonDays(days);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySoonThresholdDays, clamped);

    if (!ref.mounted) return;
    state = state.copyWith(soonThresholdDays: clamped);
  }

  Future<void> resetSoonThresholdToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySoonThresholdDays);

    if (!ref.mounted) return;
    state = state.copyWith(
      soonThresholdDays: AppSettings.defaultSoonThresholdDays,
    );
  }

  // ★追加: 連続登録の設定保存
  Future<void> setKeepAddingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKeepAdding, enabled);

    if (!ref.mounted) return;
    state = state.copyWith(isKeepAddingEnabled: enabled);
  }

  int _clampSoonDays(int value) {
    if (value < 0) return 0;
    if (value > AppSettings.maxSoonThresholdDays) {
      return AppSettings.maxSoonThresholdDays;
    }
    return value;
  }
}

final appSettingsProvider =
NotifierProvider<AppSettingsNotifier, AppSettings>(() {
  return AppSettingsNotifier();
});