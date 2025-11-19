// lib/data/dummy_data.dart
import 'package:expiry_date/models/snack_item.dart';

/// アプリの動作確認用ダミーデータ。
/// 日付は、期限切れ／もうすぐ／余裕あり が混ざるようにしています。
final List<SnackItem> dummySnacks = [
  SnackItem(
    name: 'チロルチョコ（コーヒー）', // 期限切れ想定
    expiry: DateTime(2025, 1, 10),
    price: 20,
  ),
  SnackItem(
    name: 'うまい棒 めんたい味',
    expiry: DateTime(2025, 11, 5),
    price: 10,
  ),
  SnackItem(
    name: 'ポテトチップス のり塩',
    expiry: DateTime(2025, 11, 25),
    price: 120,
  ),
  SnackItem(
    name: 'ポテトチップス うすしお',
    expiry: DateTime(2025, 12, 5),
    price: 120,
  ),
  SnackItem(
    name: 'ベビースターラーメン（チキン）',
    expiry: DateTime(2025, 10, 28),
    price: 60,
  ),
  SnackItem(
    name: 'ガブリチュウ グレープ',
    expiry: DateTime(2026, 1, 15),
    price: 30,
  ),
  SnackItem(
    name: 'キャラメルコーン（ピーナッツ入り）',
    expiry: DateTime(2025, 9, 30),
    price: 100,
  ),
  SnackItem(
    name: 'マシュマロ（プレーン）',
    expiry: DateTime(2025, 8, 20),
    price: 80,
  ),
  SnackItem(
    name: 'ラムネ菓子（ソーダ）',
    expiry: DateTime(2026, 3, 1),
    price: 50,
  ),
  SnackItem(
    name: 'チョコレート棒',
    expiry: DateTime(2025, 12, 31),
    price: 50,
  ),
];
