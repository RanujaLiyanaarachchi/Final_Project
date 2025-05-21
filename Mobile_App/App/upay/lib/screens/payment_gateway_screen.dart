import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:upay/screens/receipt_screen.dart';
import 'package:upay/l10n/app_localizations.dart';

class PaymentGatewayScreen extends StatefulWidget {
  const PaymentGatewayScreen({super.key});

  @override
  State<PaymentGatewayScreen> createState() => _PaymentGatewayScreenState();
}

class _PaymentGatewayScreenState extends State<PaymentGatewayScreen> {
  bool _payHover = false;
  bool _payPressed = false;
  bool _cancelHover = false;
  bool _cancelPressed = false;

  final TextEditingController _cardController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _cvvController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          SystemNavigator.pop(); // Exit the app
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFEF7FF),
        body: Column(
          children: [
            const SizedBox(height: 80),

            // Custom AppBar (no back button)
            Center(
              child: Text(
                t.payment,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Top Info Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 239, 247, 255),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/images/payment/payment.png',
                          width: 40,
                          height: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                "Your Name",
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "Account Number",
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(thickness: 1),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Card Input Fields
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                children: [
                  _buildInputField(
                    hint: "0000 0000 0000 0000",
                    icon: Icons.credit_card,
                    controller: _cardController,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInputField(
                          hint: "MM/YY",
                          icon: Icons.date_range,
                          controller: _expiryController,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInputField(
                          hint: "...",
                          icon: Icons.lock,
                          controller: _cvvController,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInputField(
                    hint: "Enter Cardholder's Name",
                    icon: Icons.person,
                    controller: _nameController,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Pay Amount
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F6F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${t.pay_amount}:", style: const TextStyle(fontWeight: FontWeight.w500)),
                    const Text("LKR. 50,000.00", style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),

            // Pay Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: MouseRegion(
                onEnter: (_) => setState(() => _payHover = true),
                onExit: (_) => setState(() => _payHover = false),
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _payPressed = true),
                  onTapUp: (_) => setState(() => _payPressed = false),
                  onTapCancel: () => setState(() => _payPressed = false),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ReceiptScreen(),
                      ),
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      gradient: _payPressed
                          ? LinearGradient(
                              colors: [Colors.blue.shade800, Colors.blue.shade900],
                            )
                          : _payHover
                              ? LinearGradient(
                                  colors: [Colors.blue.shade400, Colors.blue.shade600],
                                )
                              : LinearGradient(
                                  colors: [Colors.blue.shade300, Colors.blue.shade500],
                                ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: _payPressed
                              ? Colors.blue.shade900.withAlpha(100)
                              : _payHover
                                  ? Colors.blue.shade600.withAlpha(80)
                                  : Colors.blue.withAlpha(50),
                          blurRadius: 10,
                          spreadRadius: 2,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        t.pay,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 15),

            // Cancel Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: MouseRegion(
                onEnter: (_) => setState(() => _cancelHover = true),
                onExit: (_) => setState(() => _cancelHover = false),
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _cancelPressed = true),
                  onTapUp: (_) => setState(() => _cancelPressed = false),
                  onTapCancel: () => setState(() => _cancelPressed = false),
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      gradient: _cancelPressed
                          ? LinearGradient(
                              colors: [Colors.blue.shade800, Colors.blue.shade900],
                            )
                          : _cancelHover
                              ? LinearGradient(
                                  colors: [Colors.blue.shade100, Colors.blue.shade300],
                                )
                              : LinearGradient(
                                  colors: [Colors.blue.shade100, Colors.blue.shade200],
                                ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: _cancelPressed
                              ? Colors.grey.shade700.withAlpha(100)
                              : _cancelHover
                                  ? Colors.grey.shade500.withAlpha(80)
                                  : Colors.grey.withAlpha(50),
                          blurRadius: 10,
                          spreadRadius: 2,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        t.cancel,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String hint,
    required IconData icon,
    required TextEditingController controller,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          icon: Icon(icon, color: Colors.grey),
        ),
      ),
    );
  }
}
