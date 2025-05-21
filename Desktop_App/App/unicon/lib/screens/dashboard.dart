import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'pages/home.dart';
import 'pages/add_personal_details.dart';
import 'pages/add_finance_details.dart';
import 'pages/view_personal_details.dart';
import 'pages/view_finance_details.dart';
import 'pages/edit_personal_details.dart';
import 'pages/edit_finance_details.dart';
import 'pages/pay_bill.dart';
import 'pages/bill_history.dart';
import 'pages/all_customers.dart';
import 'pages/selected_customers.dart';
import 'pages/settings.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Timer _timer;
  String _time = '';
  String _date = '';
  String _weather = 'Loading...';
  Widget _currentPage = const HomePage();
  int _selectedIndex = 0;

  final List<IconData> _icons = [
    Icons.home,
    Icons.add_box,
    Icons.remove_red_eye,
    Icons.edit,
    Icons.receipt_long,
    Icons.message,
    Icons.settings,
  ];

  final List<String> _labels = [
    "Home",
    "Add",
    "View",
    "Edit",
    "Bill",
    "Message",
    "Settings",
  ];

  @override
  void initState() {
    super.initState();
    _updateTime();
    _fetchWeather();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());

    // Fullscreen on Windows
    if (Platform.isWindows) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _time = DateFormat('hh:mm:ss a').format(now);
      _date = DateFormat('EEEE, MMMM d, y').format(now);
    });
  }

  Future<void> _fetchWeather() async {
    try {
      const apiKey = '945687c33eed480b869131756251404';
      const city = 'Colombo';
      final url = Uri.parse(
        'https://api.weatherapi.com/v1/current.json?key=$apiKey&q=$city',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _weather =
              '${data['current']['temp_c']}°C, ${data['current']['condition']['text']}';
        });
      } else {
        setState(() {
          _weather = 'Unavailable';
        });
      }
    } catch (e) {
      setState(() {
        _weather = 'Error';
      });
    }
  }

  void _onNavTapped(int index) {
    setState(() => _selectedIndex = index);
    switch (index) {
      case 0:
        setState(() => _currentPage = const HomePage());
        break;
      case 1:
        _showBottomSheet(
          "Add",
          AddPersonalDetailsPage(),
          AddFinanceDetailsPage(),
        );
        break;
      case 2:
        _showBottomSheet(
          "View",
          const ViewPersonalDetailsPage(),
          const ViewFinanceDetailsPage(),
        );
        break;
      case 3:
        _showBottomSheet(
          "Edit",
          const EditPersonalDetailsPage(),
          const EditFinanceDetailsPage(),
        );
        break;
      case 4:
        _showBottomSheet("Bill", const PayBillPage(), const BillHistoryPage());
        break;
      case 5:
        _showBottomSheet(
          "Message",
          const AllCustomersPage(),
          const SelectedCustomersPage(),
        );
        break;
      case 6:
        setState(() => _currentPage = const SettingsPage());
        break;
    }
  }

  void _showBottomSheet(String title, Widget page1, Widget page2) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(
            top: 20,
            left: 16,
            right: 16,
            bottom: 30,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Center(
                    child: Text(
                      "Choose $title Option",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(thickness: 1),
              const SizedBox(height: 10),
              if (title == "Bill") ...[
                _buildOptionTile(Icons.payment_rounded, "Pay Bill", () {
                  Navigator.pop(context);
                  setState(() => _currentPage = page1);
                }),
                const SizedBox(height: 8),
                _buildOptionTile(Icons.history_rounded, "Bill History", () {
                  Navigator.pop(context);
                  setState(() => _currentPage = page2);
                }),
              ] else if (title == "Message") ...[
                _buildOptionTile(Icons.groups_rounded, "All Customers", () {
                  Navigator.pop(context);
                  setState(() => _currentPage = page1);
                }),
                const SizedBox(height: 8),
                _buildOptionTile(
                  Icons.person_pin_circle,
                  "Selected Customers",
                  () {
                    Navigator.pop(context);
                    setState(() => _currentPage = page2);
                  },
                ),
              ] else ...[
                _buildOptionTile(Icons.person, "Personal Details", () {
                  Navigator.pop(context);
                  setState(() => _currentPage = page1);
                }),
                const SizedBox(height: 8),
                _buildOptionTile(
                  Icons.account_balance_wallet,
                  "Finance Details",
                  () {
                    Navigator.pop(context);
                    setState(() => _currentPage = page2);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptionTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      tileColor: Colors.blue[50],
      leading: Icon(icon, color: Colors.blue),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
      onTap: onTap,
    );
  }

  BottomNavigationBarItem _buildNavItem(IconData icon, String label) {
    return BottomNavigationBarItem(
      icon: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(icon),
      ),
      label: label,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[50],
      appBar: AppBar(
        backgroundColor: Colors.blue,
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundImage: AssetImage('assets/images/profile.png'),
            ),
            const SizedBox(width: 10),
            const Text(
              'Administrator',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(Icons.cloud, color: Colors.white70, size: 18),
                const SizedBox(width: 5),
                Text(
                  _weather,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 10),
            child: Column(
              children: [
                Text(
                  _time,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(_date, style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: _currentPage),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.zero,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
        ),
        child: BottomNavigationBar(
          items: List.generate(
            _icons.length,
            (index) => _buildNavItem(_icons[index], _labels[index]),
          ),
          currentIndex: _selectedIndex,
          onTap: _onNavTapped,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          backgroundColor: Colors.blue,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          showUnselectedLabels: true,
        ),
      ),
    );
  }
}
