import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:expense_tracker/core/widgets/smart_selection_area.dart';
import 'package:expense_tracker/core/widgets/smart_text.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/auth/cubit/auth_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _registerMode = false;
  bool _passwordVisible = false;
  String? _validationMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _validationMessage = 'Enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setState(
        () => _validationMessage = 'Password must be at least 8 characters.',
      );
      return;
    }
    if (_registerMode && _nameController.text.trim().isEmpty) {
      setState(() => _validationMessage = 'Enter your name.');
      return;
    }
    if (_registerMode && password != _confirmPasswordController.text) {
      setState(() => _validationMessage = 'Passwords do not match.');
      return;
    }
    setState(() => _validationMessage = null);
    final cubit = context.read<AuthCubit>();
    if (_registerMode) {
      cubit.register(
        email: email,
        password: password,
        displayName: _nameController.text.trim(),
      );
      return;
    }
    cubit.login(email: email, password: password);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        final isLoading = state.status == AuthStatus.loading;
        final message =
            _validationMessage ??
            (state.status == AuthStatus.failure ? state.message : null);

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
                  registerMode: _registerMode,
                  emailController: _emailController,
                  passwordController: _passwordController,
                  confirmPasswordController: _confirmPasswordController,
                  nameController: _nameController,
                  passwordVisible: _passwordVisible,
                  onModeChanged: (value) => setState(() {
                    _registerMode = value;
                    _validationMessage = null;
                  }),
                  onPasswordVisibilityChanged: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                  onSubmit: _submit,
                  useCupertino: true,
                ),
              ),
            ),
            android: Scaffold(
              body: _LoginBody(
                isLoading: isLoading,
                message: message,
                registerMode: _registerMode,
                emailController: _emailController,
                passwordController: _passwordController,
                confirmPasswordController: _confirmPasswordController,
                nameController: _nameController,
                passwordVisible: _passwordVisible,
                onModeChanged: (value) => setState(() {
                  _registerMode = value;
                  _validationMessage = null;
                }),
                onPasswordVisibilityChanged: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                onSubmit: _submit,
                useCupertino: false,
              ),
            ),
            web: Scaffold(
              body: _LoginBody(
                isLoading: isLoading,
                message: message,
                registerMode: _registerMode,
                emailController: _emailController,
                passwordController: _passwordController,
                confirmPasswordController: _confirmPasswordController,
                nameController: _nameController,
                passwordVisible: _passwordVisible,
                onModeChanged: (value) => setState(() {
                  _registerMode = value;
                  _validationMessage = null;
                }),
                onPasswordVisibilityChanged: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                onSubmit: _submit,
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
    required this.registerMode,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.nameController,
    required this.passwordVisible,
    required this.onModeChanged,
    required this.onPasswordVisibilityChanged,
    required this.onSubmit,
    required this.useCupertino,
  });

  final bool isLoading;
  final String? message;
  final bool registerMode;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final TextEditingController nameController;
  final bool passwordVisible;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onPasswordVisibilityChanged;
  final VoidCallback onSubmit;
  final bool useCupertino;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            SmartText(
              'Expense Tracker',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            SmartText(
              registerMode
                  ? 'Create your expense account'
                  : 'Sign in to track spending and plans',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (registerMode) ...[
              TextField(
                controller: nameController,
                enabled: !isLoading,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: emailController,
              enabled: !isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              enabled: !isLoading,
              obscureText: !passwordVisible,
              onSubmitted: (_) => isLoading ? null : onSubmit(),
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: registerMode ? 'Use at least 8 characters.' : null,
                suffixIcon: IconButton(
                  tooltip: passwordVisible ? 'Hide password' : 'Show password',
                  onPressed: isLoading ? null : onPasswordVisibilityChanged,
                  icon: Icon(
                    passwordVisible ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            if (registerMode) ...[
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordController,
                enabled: !isLoading,
                obscureText: !passwordVisible,
                onSubmitted: (_) => isLoading ? null : onSubmit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (useCupertino)
              CupertinoButton.filled(
                onPressed: isLoading ? null : onSubmit,
                child: isLoading
                    ? const CupertinoActivityIndicator()
                    : SmartText(
                        registerMode ? 'Create account' : 'Sign in',
                        selectableOnWeb: false,
                      ),
              )
            else
              FilledButton.icon(
                onPressed: isLoading ? null : onSubmit,
                icon: isLoading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: SmartText(
                  registerMode ? 'Create account' : 'Sign in',
                  selectableOnWeb: false,
                ),
              ),
            TextButton(
              onPressed: isLoading ? null : () => onModeChanged(!registerMode),
              child: Text(
                registerMode
                    ? 'Already have an account? Sign in'
                    : 'Need an account? Register',
              ),
            ),
            if (!registerMode)
              TextButton(
                onPressed: isLoading
                    ? null
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Password reset is not available yet.',
                            ),
                          ),
                        );
                      },
                child: const Text('Forgot password?'),
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
    );
  }
}
