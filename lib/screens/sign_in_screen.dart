import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';

/// ログインしていないときに表示する「Googleでログイン」画面。
class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ログイン'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Googleアカウントで\nログインしてください',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text(
                    'Googleでログイン',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    await _handleSignIn(context, ref);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignIn(
      BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(authRepositoryProvider);
      final credential = await repo.signInWithGoogle();

      if (credential == null) {
        // ユーザーがキャンセルしただけなので何もしない
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログインをキャンセルしました')),
        );
        return;
      }

      // 成功時は特に何もせず、authStateChangesProvider を通じて画面側が切り替わる
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインしました')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ログインに失敗しました: $e')),
      );
    }
  }
}
