import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session_store.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool loading = false;
  bool registerMode = false;
  String error = '';

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final patientIdController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    patientIdController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (loading) return;

    FocusScope.of(context).unfocus();

    final email = emailController.text.trim();
    final password = passwordController.text;
    final patientIdText = patientIdController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        error = 'Email and password are required';
      });
      return;
    }

    setState(() {
      loading = true;
      error = '';
    });

    try {
      Map<String, dynamic> result;

      if (registerMode) {
        final pid = patientIdText.isEmpty ? null : int.tryParse(patientIdText);
        if (patientIdText.isNotEmpty && pid == null) {
          throw Exception('Patient ID must be an integer');
        }

        result = await ApiClient.instance.register(
          email: email,
          password: password,
          patientId: pid,
        );
      } else {
        result = await ApiClient.instance.login(
          email: email,
          password: password,
        );
      }

      final token = result['token']?.toString() ?? '';
      final user = result['user'] as Map<String, dynamic>?;

      if (token.isEmpty || user == null) {
        throw Exception('Invalid auth response');
      }

      if (!mounted) return;

      SessionStore.setSession(token: token, user: user);

      setState(() {
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = e.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFF0B1220),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF1F2937)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.directions_car_filled_rounded,
                    size: 48,
                    color: Color(0xFFC4B0EA),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    registerMode ? 'Create Account' : 'Login',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    registerMode
                        ? 'Create a new Smart Vehicle account'
                        : 'Login to your Smart Vehicle account',
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) {},
                    decoration: _inputDecoration('Email'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    textInputAction:
                        registerMode ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    decoration: _inputDecoration('Password'),
                  ),
                  if (registerMode) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: patientIdController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                      decoration: _inputDecoration('Patient ID (optional)'),
                    ),
                  ],
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: loading ? null : submit,
                      icon: loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              registerMode
                                  ? Icons.person_add_alt_1
                                  : Icons.login,
                            ),
                      label: Text(
                        loading
                            ? 'Please wait...'
                            : (registerMode ? 'Create Account' : 'Login'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              registerMode = !registerMode;
                              error = '';
                            });
                          },
                    child: Text(
                      registerMode
                          ? 'Already have an account? Login'
                          : 'No account yet? Register',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}