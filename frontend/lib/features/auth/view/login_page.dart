import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:expense_tracker/core/widgets/smart_selection_area.dart';
import 'package:expense_tracker/core/widgets/smart_text.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/auth/cubit/auth_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        final isLoading = state.status == AuthStatus.loading;
        final message = state.status == AuthStatus.failure
            ? state.message
            : null;

        return SmartSelectionArea(
          child: PlatformWidget(
            ios: CupertinoPageScaffold(
              navigationBar: const CupertinoNavigationBar(
                middle: SmartText('Expense Tracker'),
              ),
              child: SafeArea(
                child: _LoginBody(
                  isLoading: isLoading,
                  message: message,
                  useCupertino: true,
                ),
              ),
            ),
            android: Scaffold(
              body: _LoginBody(
                isLoading: isLoading,
                message: message,
                useCupertino: false,
              ),
            ),
            web: Scaffold(
              body: _LoginBody(
                isLoading: isLoading,
                message: message,
                useCupertino: false,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LoginBody extends StatelessWidget {
  const _LoginBody({
    required this.isLoading,
    required this.message,
    required this.useCupertino,
  });

  final bool isLoading;
  final String? message;
  final bool useCupertino;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SmartText(
                'Expense Tracker',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              SmartText(
                'Sign in with Google to continue',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              if (useCupertino)
                CupertinoButton.filled(
                  onPressed: isLoading
                      ? null
                      : () => context.read<AuthCubit>().signInWithGoogle(),
                  child: isLoading
                      ? const CupertinoActivityIndicator()
                      : const SmartText(
                          'Continue with Google',
                          selectableOnWeb: false,
                        ),
                )
              else
                FilledButton.icon(
                  onPressed: isLoading
                      ? null
                      : () => context.read<AuthCubit>().signInWithGoogle(),
                  icon: isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const SmartText(
                    'Continue with Google',
                    selectableOnWeb: false,
                  ),
                ),
              if (message != null) ...[
                const SizedBox(height: 12),
                SmartText(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
