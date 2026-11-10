import 'package:flutter/material.dart';

import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Anmelden oder Konto erstellen (per E-Mail).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _invite = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = AppScope.read(context);
    try {
      if (_register) {
        await state.register(email: _email.text.trim(), name: _name.text.trim(), password: _password.text, inviteCode: _invite.text);
      } else {
        await state.signIn(_email.text.trim(), _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? T.fieldRequired : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(T.appName, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: AppSpacing.s),
                      Text(T.loginIntro, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: AppSpacing.xl),
                      Text(_register ? T.registerTitle : T.loginTitle, style: theme.textTheme.titleLarge),
                      const SizedBox(height: AppSpacing.l),
                      if (_register) ...[
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: T.name),
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          validator: _required,
                        ),
                        const SizedBox(height: AppSpacing.m),
                      ],
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: T.email),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '') ? null : T.emailInvalid,
                      ),
                      const SizedBox(height: AppSpacing.m),
                      TextFormField(
                        controller: _password,
                        decoration: InputDecoration(labelText: T.password, helperText: _register ? T.passwordHint : null),
                        obscureText: true,
                        autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                        textInputAction: _register ? TextInputAction.next : TextInputAction.done,
                        onFieldSubmitted: (_) => _register ? null : _submit(),
                        validator: (v) => _register ? ((v ?? '').length < 10 ? T.passwordTooShort : null) : _required(v),
                      ),
                      if (_register) ...[
                        const SizedBox(height: AppSpacing.m),
                        TextFormField(
                          controller: _invite,
                          decoration: const InputDecoration(labelText: T.inviteCode, helperText: T.inviteCodeHint, helperMaxLines: 2),
                          textCapitalization: TextCapitalization.characters,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: AppSpacing.m),
                        Text(T.consentRegister, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                      const SizedBox(height: AppSpacing.l),
                      if (_error != null) Notice(_error!, icon: Icons.error_outline, color: theme.colorScheme.error),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_register ? T.registerButton : T.loginButton),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                        child: Text(_register ? T.toLogin : T.toRegister),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
