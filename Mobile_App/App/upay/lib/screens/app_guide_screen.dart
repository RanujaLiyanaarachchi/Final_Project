import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppGuideScreen extends StatefulWidget {
  const AppGuideScreen({super.key});

  @override
  AppGuideScreenState createState() => AppGuideScreenState();
}

class AppGuideScreenState extends State<AppGuideScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isNavigating = false;

  final List<GuideItem> _guideItems = [
    GuideItem(
      title: "Welcome to UPay",
      description:
          "Your all-in-one solution for secure digital payments and financial management.",
      icon: Icons.account_balance_wallet_rounded,
      color: const Color(0xFF6A1B9A),
      illustration: 'assets/images/guide/welcome.png',
      tips: [
        "Access all features from the dashboard",
        "Easily navigate with bottom menu",
        "Check account balance at a glance",
      ],
    ),
    GuideItem(
      title: "Dashboard",
      description:
          "Your financial control center with all key information and quick actions.",
      icon: Icons.dashboard_rounded,
      color: const Color(0xFF1565C0),
      illustration: 'assets/images/guide/dashboard.png',
      tips: [
        "View your balance at the top",
        "Access all services with quick action buttons",
        "See recent transactions instantly",
        "Check important notifications directly",
      ],
    ),
    GuideItem(
      title: "Profile Page",
      description:
          "Manage your personal information and account details securely.",
      icon: Icons.person_rounded,
      color: const Color(0xFF0D47A1),
      illustration: 'assets/images/guide/profile.png',
      tips: [
        "Update your personal information",
        "Change your profile photo",
        "View your account number and details",
        "Manage linked payment methods",
      ],
    ),
    GuideItem(
      title: "Notifications",
      description:
          "Stay updated with transaction alerts, payment reminders, and important updates.",
      icon: Icons.notifications_rounded,
      color: const Color(0xFFD81B60),
      illustration: 'assets/images/guide/notifications.png',
      tips: [
        "Get real-time transaction alerts",
        "Mark notifications as read",
        "Customize notification preferences in settings",
        "Never miss important payment deadlines",
      ],
    ),
    GuideItem(
      title: "Liabilities",
      description:
          "Track and manage all your loans, credit cards, and other financial obligations.",
      icon: Icons.account_balance_rounded,
      color: const Color(0xFF6D4C41),
      illustration: 'assets/images/guide/liability.png',
      tips: [
        "View all your loans in one place",
        "Track remaining balances and due dates",
        "Get payment reminders before due dates",
        "Download statements for your records",
      ],
    ),
    GuideItem(
      title: "Make Payments",
      description:
          "Pay bills, transfer funds, and make purchases with just a few taps.",
      icon: Icons.payments_rounded,
      color: const Color(0xFF00897B),
      illustration: 'assets/images/guide/payments.png',
      tips: [
        "Tap the Pay button for quick transactions",
        "Save frequent payments as templates",
        "Schedule future payments",
        "Get instant confirmation receipts",
      ],
    ),
    GuideItem(
      title: "Bill Payments",
      description:
          "Pay all your utility bills, subscriptions, and other regular expenses easily.",
      icon: Icons.receipt_long_rounded,
      color: const Color(0xFF5D4037),
      illustration: 'assets/images/guide/bill.png',
      tips: [
        "Pay electricity, water, internet bills",
        "Set up automatic bill payments",
        "Get reminders before due dates",
        "View payment history for each biller",
      ],
    ),
    GuideItem(
      title: "Support",
      description:
          "We're here to help whenever you need assistance with your account or transactions.",
      icon: Icons.support_agent_rounded,
      color: const Color(0xFF4A148C),
      illustration: 'assets/images/guide/support.png',
      tips: [
        "Access 24/7 customer support",
        "Chat with support agents in real-time",
        "Browse FAQs for quick answers",
        "Submit and track support tickets",
      ],
    ),
    GuideItem(
      title: "Settings",
      description:
          "Customize your app experience and manage security preferences.",
      icon: Icons.settings_rounded,
      color: const Color(0xFF455A64),
      illustration: 'assets/images/guide/settings.png',
      tips: [
        "Enable biometric authentication",
        "Manage notification preferences",
        "Change app language and themes",
        "Control privacy and security options",
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _navigateToSettingsScreen() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    Navigator.of(context).pop();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;

      if (!Navigator.of(context).canPop()) {
        Navigator.of(
          context,
        ).pushReplacementNamed('/main', arguments: {'initialTab': 4});
      } else {
        Navigator.of(context).pushNamed('/main', arguments: {'initialTab': 4});
      }
    });
  }

  void _skipToSettingsPage() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    final int lastPageIndex = _guideItems.length - 1;

    if (_currentPage == lastPageIndex) {
      _navigateToSettingsScreen();
      return;
    }

    _pageController
        .animateToPage(
          lastPageIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        )
        .then((_) {
          setState(() {
            _currentPage = lastPageIndex;
            _isNavigating = false;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentPage == 0 && !_isNavigating,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentPage > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FD),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading:
              _currentPage > 0
                  ? IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios,
                      color: Colors.black87,
                    ),
                    onPressed: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  )
                  : IconButton(
                    icon: const Icon(Icons.close, color: Colors.black87),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 32,
                          width: 32,
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "UPay",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),

                    TextButton(
                      onPressed: _isNavigating ? null : _skipToSettingsPage,
                      child: Text(
                        "Skip",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: LinearProgressIndicator(
                  value: (_currentPage + 1) / _guideItems.length,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).primaryColor,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _guideItems.length,
                  onPageChanged: (int page) {
                    setState(() {
                      _currentPage = page;
                    });
                  },
                  itemBuilder: (context, index) {
                    return GuidePage(item: _guideItems[index]);
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _guideItems.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 8,
                          width: _currentPage == index ? 24 : 8,
                          decoration: BoxDecoration(
                            color:
                                _currentPage == index
                                    ? _guideItems[_currentPage].color
                                    : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _currentPage > 0
                            ? IconButton(
                              onPressed:
                                  _isNavigating
                                      ? null
                                      : () {
                                        _pageController.previousPage(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.easeInOut,
                                        );
                                      },
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.arrow_back_ios_new,
                                  size: 16,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            )
                            : const SizedBox(width: 40),

                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _guideItems[_currentPage].color,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 36,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 2,
                          ),
                          onPressed:
                              _isNavigating
                                  ? null
                                  : () {
                                    if (_currentPage < _guideItems.length - 1) {
                                      _pageController.nextPage(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        curve: Curves.easeInOut,
                                      );
                                    } else {
                                      _navigateToSettingsScreen();
                                    }
                                  },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentPage < _guideItems.length - 1
                                    ? "Next"
                                    : "Get Started",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _currentPage < _guideItems.length - 1
                                    ? Icons.arrow_forward
                                    : Icons.check_circle,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GuideItem {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String illustration;
  final List<String> tips;

  GuideItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.illustration,
    required this.tips,
  });
}

class GuidePage extends StatelessWidget {
  final GuideItem item;

  const GuidePage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            Container(
              height: 200,
              width: 360,
              decoration: BoxDecoration(
                color: item.color.withAlpha((0.05 * 255).round()),
                borderRadius: BorderRadius.circular(24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  item.illustration,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(
                        item.icon,
                        size: 100,
                        color: item.color.withAlpha((0.6 * 255).round()),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 40),

            Text(
              item.title,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: item.color,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            Text(
              item.description,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade800,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: item.color,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Quick Tips",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: item.color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...item.tips.map(
                    (tip) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: item.color.withAlpha((0.7 * 255).round()),
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tip,
                              style: const TextStyle(fontSize: 14, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
