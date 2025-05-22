import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upay/providers/language_provider.dart';
import 'package:upay/screens/welcome_screen.dart';

class LanguageSelectionScreen extends StatelessWidget {
  const LanguageSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    const headingColor = Color(0xFF303663);
    const subTextColor = Color(0xFF6B7280);
    const circleColor = Color.fromRGBO(57, 87, 237, 0.1);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Color(0xFFF0F4FF)],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: -80,
                  right: -80,
                  child: Container(
                    width: size.width * 0.4,
                    height: size.width * 0.4,
                    decoration: const BoxDecoration(
                      color: circleColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  bottom: -80,
                  left: -80,
                  child: Container(
                    width: size.width * 0.5,
                    height: size.width * 0.5,
                    decoration: const BoxDecoration(
                      color: circleColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: size.height * 0.06),

                    const Text(
                      "Welcome to UPay",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: headingColor,
                      ),
                    ),

                    SizedBox(height: size.height * 0.01),

                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        "Please select your preferred language",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: subTextColor,
                          height: 1.5,
                        ),
                      ),
                    ),

                    SizedBox(height: size.height * 0.04),

                    SizedBox(
                      height: size.height * 0.34,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.05,
                        ),
                        child: Image.asset(
                          'assets/images/language/language_selection.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(30),
                            topRight: Radius.circular(30),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x1A000000),
                              blurRadius: 20,
                              offset: Offset(0, -5),
                            ),
                          ],
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.12,
                          vertical: size.height * 0.03,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Choose Your Language",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: headingColor,
                              ),
                            ),

                            SizedBox(height: size.height * 0.025),

                            const LanguageButton(
                              language: 'English',
                              locale: Locale('en'),
                              letter: 'A',
                            ),

                            SizedBox(height: size.height * 0.018),

                            const LanguageButton(
                              language: 'සිංහල',
                              locale: Locale('si'),
                              letter: 'අ',
                            ),

                            SizedBox(height: size.height * 0.018),

                            const LanguageButton(
                              language: 'தமிழ்',
                              locale: Locale('ta'),
                              letter: 'அ',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LanguageButton extends StatefulWidget {
  final String language;
  final Locale locale;
  final String letter;

  const LanguageButton({
    super.key,
    required this.language,
    required this.locale,
    required this.letter,
  });

  @override
  State<LanguageButton> createState() => _LanguageButtonState();
}

class _LanguageButtonState extends State<LanguageButton> {
  bool _isPressed = false;

  Future<void> _handleLanguageSelection() async {
    Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).setLocale(widget.locale);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', widget.locale.languageCode);
    await prefs.setBool('isLanguageSelected', true);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder:
            (context, animation, secondaryAnimation) => const WelcomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttonColor = _isPressed ? Colors.blue : Colors.white;
    final textColor = _isPressed ? Colors.white : const Color(0xFF303663);
    final letterBgColor =
        _isPressed
            ? const Color.fromRGBO(255, 255, 255, 0.2)
            : const Color.fromARGB(255, 249, 250, 252);
    final letterColor = _isPressed ? Colors.white : Colors.blue;
    final iconColor = _isPressed ? Colors.white : const Color(0xFFBBBFD0);
    final borderColor = _isPressed ? Colors.blue : const Color(0xFFE5E7EB);

    final boxShadow =
        _isPressed
            ? [
              BoxShadow(
                color: Colors.blue.withAlpha((0.3 * 255).round()),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ]
            : <BoxShadow>[];

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: _handleLanguageSelection,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        decoration: BoxDecoration(
          color: buttonColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: boxShadow,
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: letterBgColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  widget.letter,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: letterColor,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 15),

            Text(
              widget.language,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),

            const Spacer(),

            Icon(Icons.arrow_forward_ios, size: 16, color: iconColor),
          ],
        ),
      ),
    );
  }
}
