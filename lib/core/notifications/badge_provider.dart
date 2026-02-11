import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expiry_date/core/snacks/snack_repository.dart';
import 'package:expiry_date/core/notifications/notification_service.dart';
import 'package:expiry_date/core/settings/app_settings.dart';

/// 在庫リストと設定を監視し、条件に合う商品数をアイコンバッジに反映させる
final badgeProvider = Provider<void>((ref) {
  // 1. 在庫リスト (snackListStreamProvider) を監視
  // ※ SnackRepository 内で currentShopIdProvider を watch しているため、
  // 店舗切り替え時も自動でここが再実行されます。
  final snacksAsync = ref.watch(snackListStreamProvider);

  // 2. 設定 (soonThresholdDays) を監視
  final settings = ref.watch(appSettingsProvider);

  // 3. 通知サービスを取得
  final notificationService = ref.read(notificationServiceProvider);

  snacksAsync.whenData((snacks) {
    // ユーザー設定の「もうすぐ」判定日数
    final warningDays = settings.soonThresholdDays;

    final now = DateTime.now();
    // 時刻を切り捨てて今日（0:00:00）を基準にする
    final today = DateTime(now.year, now.month, now.day);

    // 判定基準日（今日 + 設定日数）
    final threshold = today.add(Duration(days: warningDays));

    // 「期限切れ」および「設定日数以内」の商品をカウント
    final alertCount = snacks.where((snack) {
      // 期限が閾値（threshold）と同じか、それより前であればカウント
      return snack.expiry.isBefore(threshold) ||
          snack.expiry.isAtSameMomentAs(threshold);
    }).length;

    print('【Badge Debug】 バッジの計算結果: $alertCount 件');
    // アイコンのバッジ（赤丸数字）を更新
    notificationService.updateBadgeCount(alertCount);
  });
});