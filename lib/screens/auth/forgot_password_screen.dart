import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../services/api_service.dart';

/// Step 1: request a password reset link.
///
/// The email is validated client-side for a quick guard, while the server
/// performs authoritative validation (see mu-plugin `zzmore-password-reset.php`).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _api = ApiService();
  bool _isLoading = false;
  String? _message;
  bool _isSuccess = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _isSuccess = false;
        _message = 'Please enter a valid email address.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    final error = await _api.requestPasswordReset(email);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (error == null) {
        _isSuccess = true;
        _message =
            'If an account exists for this email, a password reset link has been sent. '
            'Please check your inbox (and spam folder).';
      } else {
        _isSuccess = false;
        _message = error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.goldColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outlined,
                      color: AppColors.goldColor, size: 36),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Forgot Password',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.inkColor,
                    fontFamily: 'Fraunces'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your registered email and we will send you a secure link to reset your password.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoftColor, fontSize: 14),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _sendResetLink(),
                decoration: InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: const Icon(Icons.email_outlined,
                      color: AppColors.inkSoftColor),
                  filled: true,
                  fillColor: AppColors.whiteColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isSuccess
                        ? AppColors.goldColor.withOpacity(0.1)
                        : AppColors.coralColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _isSuccess
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: _isSuccess
                            ? AppColors.goldColor
                            : AppColors.coralColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _isSuccess
                                ? AppColors.inkColor
                                : AppColors.coralColor,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _sendResetLink,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldColor,
                  foregroundColor: AppColors.whiteColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Send Reset Link',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ResetPasswordScreen()),
                        );
                      },
                child: const Text('I already have a reset key',
                    style: TextStyle(
                        color: AppColors.goldColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Remembered your password?',
                      style: TextStyle(
                          color: AppColors.inkSoftColor, fontSize: 13)),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Back to login',
                        style: TextStyle(
                            color: AppColors.goldColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step 2: set a new password using the reset key delivered by email.
class ResetPasswordScreen extends StatefulWidget {
  final String? initialKey;
  final String? initialLogin;

  const ResetPasswordScreen({super.key, this.initialKey, this.initialLogin});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _loginCtrl;
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _api = ApiService();
  bool _isLoading = false;
  bool _obscure = true;
  String? _message;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.initialKey ?? '');
    _loginCtrl = TextEditingController(text: widget.initialLogin ?? '');
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _loginCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    final key = _keyCtrl.text.trim();
    final login = _loginCtrl.text.trim();
    final password = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (key.isEmpty || login.isEmpty) {
      setState(() {
        _isSuccess = false;
        _message = 'Please enter the reset key and your username or email.';
      });
      return;
    }
    if (password.length < 8) {
      setState(() {
        _isSuccess = false;
        _message = 'New password must be at least 8 characters.';
      });
      return;
    }
    if (password != confirm) {
      setState(() {
        _isSuccess = false;
        _message = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    final error = await _api.resetPassword(key, login, password);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (error == null) {
        _isSuccess = true;
        _message = 'Your password has been updated. You can now sign in.';
      } else {
        _isSuccess = false;
        _message = error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.indigoColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.password_outlined,
                      color: AppColors.indigoColor, size: 36),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Set New Password',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.inkColor,
                    fontFamily: 'Fraunces'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the reset key from your email along with your login to choose a new password.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoftColor, fontSize: 14),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _keyCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Reset key (from email)',
                  prefixIcon: const Icon(Icons.vpn_key,
                      color: AppColors.inkSoftColor),
                  filled: true,
                  fillColor: AppColors.whiteColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _loginCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Username or email',
                  prefixIcon: const Icon(Icons.person_outline,
                      color: AppColors.inkSoftColor),
                  filled: true,
                  fillColor: AppColors.whiteColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'New password',
                  prefixIcon: const Icon(Icons.lock_outlined,
                      color: AppColors.inkSoftColor),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.inkSoftColor),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  filled: true,
                  fillColor: AppColors.whiteColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _resetPassword(),
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: const Icon(Icons.lock_outlined,
                      color: AppColors.inkSoftColor),
                  filled: true,
                  fillColor: AppColors.whiteColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isSuccess
                        ? AppColors.goldColor.withOpacity(0.1)
                        : AppColors.coralColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _isSuccess
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: _isSuccess
                            ? AppColors.goldColor
                            : AppColors.coralColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _isSuccess
                                ? AppColors.inkColor
                                : AppColors.coralColor,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _resetPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldColor,
                  foregroundColor: AppColors.whiteColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Reset Password',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already reset it?',
                      style: TextStyle(
                          color: AppColors.inkSoftColor, fontSize: 13)),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Back to login',
                        style: TextStyle(
                            color: AppColors.goldColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
