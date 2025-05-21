import 'package:flutter/material.dart';
import 'package:upay/screens/payment_details_screen.dart';
import 'package:upay/l10n/app_localizations.dart';

class TotalPayableScreen extends StatelessWidget {
  const TotalPayableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    double payableAmount = 1500.00; // Example amount

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.total_payable)),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Title Text
            Text(
              AppLocalizations.of(context)!.total_amount_due,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            
            // Payable Amount Text
            Text(
              "\$$payableAmount",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 20),
            
            // Pay Button
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PaymentDetailsScreen()),
                );
              },
              child: Text(AppLocalizations.of(context)!.pay),
            ),
          ],
        ),
      ),
    );
  }
}
