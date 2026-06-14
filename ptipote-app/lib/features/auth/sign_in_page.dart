import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  static final Future<void> _googleSignInReady = GoogleSignIn.instance.initialize();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _createAccount = false;
  bool _busy = false;
  bool _googleBusy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.length < 6) {
      setState(() => _error = 'Entre un email et un mot de passe de 6 caracteres minimum.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_createAccount) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _error = _readableAuthError(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleBusy = true;
      _error = null;
    });

    try {
      await _googleSignInReady;
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return;
      setState(() => _error = error.description ?? 'Connexion Google impossible.');
    } on FirebaseAuthException catch (error) {
      setState(() => _error = _readableAuthError(error));
    } catch (error) {
      setState(() => _error = 'Connexion Google impossible: $error');
    } finally {
      if (mounted) {
        setState(() => _googleBusy = false);
      }
    }
  }

  String _readableAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
        return 'Un compte existe deja avec cet email via une autre methode de connexion.';
      case 'email-already-in-use':
        return 'Un compte existe deja avec cet email.';
      case 'invalid-email':
        return 'Email invalide.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email ou mot de passe incorrect.';
      case 'weak-password':
        return 'Mot de passe trop faible.';
      default:
        return error.message ?? 'Connexion impossible.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _createAccount ? 'Créer un compte' : 'Connexion';
    final anyBusy = _busy || _googleBusy;

    return Scaffold(
      appBar: AppBar(title: const Text('PTIPOTE')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: anyBusy ? null : _signInWithGoogle,
            icon: _googleBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.account_circle),
            label: Text(_googleBusy ? 'Connexion Google...' : 'Continuer avec Google'),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
          TextField(
            controller: _emailController,
            enabled: !anyBusy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Email',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            enabled: !anyBusy,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Mot de passe',
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Créer un nouveau compte'),
            value: _createAccount,
            onChanged: anyBusy ? null : (value) => setState(() => _createAccount = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: anyBusy ? null : _submit,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(_busy ? 'Veuillez patienter...' : title),
          ),
        ],
      ),
    );
  }
}
