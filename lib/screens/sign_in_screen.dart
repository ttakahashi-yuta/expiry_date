import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';

/// ログインしていないときに表示するログイン画面。
///
/// iOS（App Store）向けに Appleログインも提供する。
/// Android 等では従来通り Google のみ表示。
class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  bool _shouldShowAppleButton() {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showApple = _shouldShowAppleButton();

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
              Text(
                showApple
                    ? 'Google または Apple で\nログインしてください'
                    : 'Googleアカウントで\nログインしてください',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Google
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
                    await _handleSignInWithGoogle(context, ref);
                  },
                ),
              ),

              if (showApple) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.apple),
                    label: const Text(
                      'Appleでログイン',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      await _handleSignInWithApple(context, ref);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignInWithGoogle(
      BuildContext context,
      WidgetRef ref,
      ) async {
    try {
      final repo = ref.read(authRepositoryProvider);
      final credential = await repo.signInWithGoogle();

      if (credential == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログインをキャンセルしました')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインしました')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ログインに失敗しました: $e')),
      );
    }
  }

  Future<void> _handleSignInWithApple(
      BuildContext context,
      WidgetRef ref,
      ) async {
    try {
      final repo = ref.read(authRepositoryProvider);
      final credential = await repo.signInWithApple();

      if (credential == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログインをキャンセルしました')),
        );
        return;
      }

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
