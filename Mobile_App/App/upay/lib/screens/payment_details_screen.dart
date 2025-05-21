import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:upay/screens/pay_screen.dart';

class PaymentDetailsScreen extends StatefulWidget {
  const PaymentDetailsScreen({super.key});

  @override
  State<PaymentDetailsScreen> createState() => _PaymentDetailsScreenState();
}

class _PaymentDetailsScreenState extends State<PaymentDetailsScreen> {
  final TextEditingController accountNumberController = TextEditingController();
  final TextEditingController nicController = TextEditingController();
  final TextEditingController amountController = TextEditingController();

  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final String today = DateFormat('dd - MM - yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFFEF7FF),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 80),

          // Custom AppBar (same as LiabilityScreen)
          Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(10.0),
                      child: Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                t.payment,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),

          const SizedBox(height: 50),

          // Top Info Section (Styled same as LiabilityScreen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                          children: [
                            Text(
                              t.pay_bill,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              today,
                              style: const TextStyle(color: Colors.grey),
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

          const SizedBox(height: 25),

          // Input Fields
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Column(
              children: [
                _buildInputField(
                  controller: accountNumberController,
                  hint: t.account_number,
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  controller: nicController,
                  hint: t.nic,
                  icon: Icons.credit_card_outlined,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  controller: amountController,
                  hint: t.amount,
                  icon: Icons.attach_money,
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // Next Button (Styled like SignInScreen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: MouseRegion(
              onEnter: (_) => setState(() => _isHovered = true),
              onExit: (_) => setState(() => _isHovered = false),
              child: GestureDetector(
                onTapDown: (_) => setState(() => _isPressed = true),
                onTapUp: (_) => setState(() => _isPressed = false),
                onTapCancel: () => setState(() => _isPressed = false),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PayScreen()),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: _isPressed
                        ? LinearGradient(colors: [Colors.blue.shade800, Colors.blue.shade900])
                        : _isHovered
                            ? LinearGradient(colors: [Colors.blue.shade400, Colors.blue.shade600])
                            : LinearGradient(colors: [Colors.blue.shade300, Colors.blue.shade500]),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: _isPressed
                            ? Colors.blue.shade900.withAlpha((0.4 * 255).toInt())
                            : _isHovered
                                ? Colors.blue.shade600.withAlpha((0.3 * 255).toInt())
                                : Colors.blue.withAlpha((0.2 * 255).toInt()),
                        blurRadius: 10,
                        spreadRadius: 2,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      t.next,
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
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
    );
  }
}
