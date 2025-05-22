import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  LanguageProvider([Locale? locale]) {
    _locale = locale ?? const Locale('en');
  }

  Locale get locale => _locale;

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("language", locale.languageCode);
  }
}
