import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    required this.soonThresholdDays,
  });

  /// 「もうすぐ」判定（daysLeft <= soonThresholdDays で “もうすぐ”）
  final int soonThresholdDays;

  static const int defaultSoonThresholdDays = 30;
  static const int maxSoonThresholdDays = 3650; // 10年

  AppSettings copyWith({
    int? soonThresholdDays,
  }) {
    return AppSettings(
      soonThresholdDays: soonThresholdDays ?? this.soonThresholdDays,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings && other.soonThresholdDays == soonThresholdDays;
  }

  @override
  int get hashCode => soonThresholdDays.hashCode;
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const String _keySoonThresholdDays = 'soonThresholdDays';

  @override
  AppSettings build() {
    // ★ build中は state が未初期化の瞬間があるので、非同期ロードは build の外へ
    Future.microtask(_loadFromPrefs);

    return const AppSettings(
      soonThresholdDays: AppSettings.defaultSoonThresholdDays,
    );
  }

  Future<void> _loadFromPrefs() async {
    // buildが返った後に呼ばれるので、ここで state を読むのはOK
    final before = state;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_keySoonThresholdDays);
    if (saved == null) return;

    // ユーザー操作などで state が変わっていたら、読み込み結果で上書きしない
    if (!ref.mounted) return;
    if (state != before) return;

    final clamped = _clampSoonDays(saved);
    state = state.copyWith(soonThresholdDays: clamped);
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
