import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'dashboard.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  // Add focus nodes for field navigation
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _submitFocusNode = FocusNode();

  String? errorMessage;
  bool isLoading = false;

  @override
  void dispose() {
    // Clean up the focus nodes when done
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _submitFocusNode.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty && password.isEmpty) {
      setState(() {
        errorMessage = 'Enter correct email and password.';
        isLoading = false;
      });
      return;
    } else if (email.isEmpty) {
      setState(() {
        errorMessage = 'Enter valid email address.';
        isLoading = false;
      });
      return;
    } else if (password.isEmpty) {
      setState(() {
        errorMessage = 'Enter correct password.';
        isLoading = false;
      });
      return;
    }

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            errorMessage = 'No user found for that email.';
            break;
          case 'wrong-password':
            errorMessage = 'Incorrect password.';
            break;
          case 'invalid-email':
            errorMessage = 'The email address is not valid.';
            break;
          default:
            errorMessage = 'Enter valid data and retry.';
        }
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _hideError() {
    if (errorMessage != null) {
      setState(() {
        errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 500;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            width: isSmallScreen ? double.infinity : 400,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_person_rounded,
                  size: 80,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Welcome Back 🖐',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 40),

                TextField(
                  controller: emailController,
                  focusNode: _emailFocusNode,
                  onTap: _hideError,
                  // Enable enter key navigation
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) {
                    FocusScope.of(context).requestFocus(_passwordFocusNode);
                  },
                  decoration: InputDecoration(
                    hintText: 'Enter your email',
                    labelText: 'Email',
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    filled: true,
                    fillColor: Colors.grey[200],
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: true,
                  onTap: _hideError,
                  // Enable enter key to submit form
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!isLoading) {
                      _signIn();
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    labelText: 'Password',
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    filled: true,
                    fillColor: Colors.grey[200],
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 34,
                ), // Updated spacing after removing the forgot button

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _signIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child:
                        isLoading
                            ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: SpinKitFadingCircle(
                                color: Color.fromARGB(0, 255, 255, 255),
                                size: 50.0,
                              ),
                            )
                            : const Text('Sign In'),
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  height: 20,
                  child:
                      errorMessage != null
                          ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 18,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                          : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
