import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:upay/screens/dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upay/services/secure_storage_service.dart';
import 'package:intl/intl.dart';

class ReceiptScreen extends StatefulWidget {
  final String? amount;
  final String? accountNumber;
  final String? customerName;
  final bool fromPayment;

  const ReceiptScreen({
    super.key,
    this.amount,
    this.accountNumber,
    this.customerName,
    this.fromPayment = false,
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  String _amount = "0.00";
  String _accountNumber = "";
  String _customerName = "";
  bool _isLoading = true;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final currencyFormatter = NumberFormat.currency(
    symbol: 'LKR ',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadPaymentDetails();
  }

  Future<void> _loadPaymentDetails() async {
    try {
      debugPrint("Loading payment details...");

      if (widget.amount != null &&
          widget.amount!.isNotEmpty &&
          widget.amount != "0.00") {
        try {
          double amountValue = double.parse(widget.amount!.replaceAll(',', ''));
          _amount = currencyFormatter.format(amountValue).trim();
          _amount = _amount.replaceAll('LKR', 'LKR ').trim();
        } catch (e) {
          _amount = widget.amount!;
        }
        debugPrint("Using amount from widget parameter: $_amount");
      } else {
        final nic = await SecureStorageService.getUserNic();
        if (nic != null && nic.isNotEmpty) {
          debugPrint("Looking up payments with NIC: $nic");

          final customerSnapshot =
              await _firestore
                  .collection('customers')
                  .where('nic', isEqualTo: nic)
                  .limit(1)
                  .get();

          if (customerSnapshot.docs.isNotEmpty) {
            final customerId = customerSnapshot.docs.first.id;
            debugPrint("Found customer with ID: $customerId");

            final paymentsSnapshot =
                await _firestore
                    .collection('payments')
                    .where('customerId', isEqualTo: customerId)
                    .orderBy('createdAt', descending: true)
                    .limit(1)
                    .get();

            if (paymentsSnapshot.docs.isNotEmpty) {
              final payment = paymentsSnapshot.docs.first.data();

              dynamic amount =
                  payment['paymentAmount'] ?? payment['amount'] ?? 0;

              num paymentAmount;
              if (amount is num) {
                paymentAmount = amount;
              } else {
                try {
                  paymentAmount = num.parse(
                    amount.toString().replaceAll(',', ''),
                  );
                } catch (_) {
                  paymentAmount = 0;
                }
              }

              _amount = currencyFormatter.format(paymentAmount).trim();
              debugPrint("Using amount from Firestore payment: $_amount");
            }
          }
        }

        if (_amount == "0.00") {
          final prefs = await SharedPreferences.getInstance();

          String? lastPaymentAmount = prefs.getString('last_payment_amount');
          if (lastPaymentAmount.isNotEmpty &&
              lastPaymentAmount != "0.00") {
            try {
              double amountValue = double.parse(
                lastPaymentAmount.replaceAll(',', ''),
              );
              _amount = currencyFormatter.format(amountValue).trim();
            } catch (e) {
              _amount = lastPaymentAmount;
            }
            debugPrint("Using amount from last_payment_amount: $_amount");
          } else {
            String? paymentAmount = prefs.getString('payment_amount');
            if (paymentAmount.isNotEmpty &&
                paymentAmount != "0.00") {
              try {
                double amountValue = double.parse(
                  paymentAmount.replaceAll(',', ''),
                );
                _amount = currencyFormatter.format(amountValue).trim();
              } catch (e) {
                _amount = paymentAmount;
              }
              debugPrint("Using amount from payment_amount: $_amount");
            }
          }
        }
      }

      if (widget.customerName != null && widget.customerName!.isNotEmpty) {
        _customerName = widget.customerName!;
        debugPrint("Using customer name from widget parameter: $_customerName");
      }

      if (widget.accountNumber != null && widget.accountNumber!.isNotEmpty) {
        _accountNumber = widget.accountNumber!;
        debugPrint(
          "Using account number from widget parameter: $_accountNumber",
        );
      }

      if (_customerName.isEmpty || _accountNumber.isEmpty) {
        final nic = await SecureStorageService.getUserNic();
        debugPrint("Retrieved NIC from secure storage: $nic");

        if (nic != null && nic.isNotEmpty) {
          debugPrint("Looking up customer with NIC: $nic");
          final customerSnapshot =
              await _firestore
                  .collection('customers')
                  .where('nic', isEqualTo: nic)
                  .limit(1)
                  .get();

          if (customerSnapshot.docs.isNotEmpty) {
            final customerDoc = customerSnapshot.docs.first;
            final customerId = customerDoc.id;
            debugPrint("Found customer with ID: $customerId");

            if (_customerName.isEmpty) {
              String firstName = customerDoc.data()['firstName'] ?? '';
              String lastName = customerDoc.data()['lastName'] ?? '';
              _customerName = '$firstName $lastName'.trim();

              if (_customerName.isEmpty) {
                _customerName = customerDoc.data()['name'] ?? '';
              }

              if (_customerName.isEmpty) {
                _customerName = customerDoc.data()['fullName'] ?? 'Unknown';
              }

              debugPrint("Set customer name to: $_customerName");
            }

            if (_accountNumber.isEmpty) {
              debugPrint(
                "Looking up finance records for customer ID: $customerId",
              );
              final financeSnapshot =
                  await _firestore
                      .collection('finances')
                      .where('customerId', isEqualTo: customerId)
                      .limit(1)
                      .get();

              if (financeSnapshot.docs.isNotEmpty) {
                _accountNumber =
                    financeSnapshot.docs.first.data()['accountNumber'] ?? '';
                debugPrint("Found account number: $_accountNumber");
              }
            }

            if (_amount == "0.00") {
              final paymentsSnapshot =
                  await _firestore
                      .collection('payments')
                      .where('customerId', isEqualTo: customerId)
                      .orderBy('createdAt', descending: true)
                      .limit(1)
                      .get();

              if (paymentsSnapshot.docs.isNotEmpty) {
                final payment = paymentsSnapshot.docs.first.data();
                dynamic amount =
                    payment['paymentAmount'] ?? payment['amount'] ?? 0;

                if (amount is num) {
                  _amount = currencyFormatter.format(amount).trim();
                  debugPrint("Using amount from payments collection: $_amount");
                } else if (amount is String && amount.isNotEmpty) {
                  try {
                    double amountValue = double.parse(
                      amount.replaceAll(',', ''),
                    );
                    _amount = currencyFormatter.format(amountValue).trim();
                  } catch (e) {
                    _amount = amount;
                  }
                  debugPrint(
                    "Using string amount from payments collection: $_amount",
                  );
                }
              }
            }
          } else {
            debugPrint("No customer found with NIC: $nic");
          }
        } else {
          debugPrint("NIC not found in secure storage");
        }

        if (_customerName.isEmpty || _accountNumber.isEmpty) {
          debugPrint("Using fallback from shared preferences");
          final prefs = await SharedPreferences.getInstance();

          if (_customerName.isEmpty) {
            _customerName = prefs.getString('customer_name') ?? 'Unknown';
            debugPrint("Set customer name from shared prefs: $_customerName");
          }

          if (_accountNumber.isEmpty) {
            _accountNumber = prefs.getString('account_number') ?? 'Unknown';
            debugPrint("Set account number from shared prefs: $_accountNumber");
          }
        }
      }

      if (!_amount.startsWith('LKR') && _amount != "0.00") {
        try {
          double amountValue = double.parse(_amount.replaceAll(',', ''));
          _amount = currencyFormatter.format(amountValue).trim();
          _amount =
              _amount
                  .replaceAll('LKR', 'LKR ')
                  .trim(); // Ensure space after currency
          debugPrint("Formatted amount: $_amount");
        } catch (e) {
          debugPrint("Error formatting amount: $e");
        }
      }

      if (_amount == "0.00" || _amount.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final savedAmount = prefs.getString('payment_amount');
        if (savedAmount != null && savedAmount.isNotEmpty) {
          try {
            double amountValue = double.parse(savedAmount.replaceAll(',', ''));
            _amount = currencyFormatter.format(amountValue).trim();
          } catch (_) {
            _amount = savedAmount;
          }
        } else {
          final standardMonthlyAmount = prefs.getString(
            'monthly_installment_amount',
          );
          if (standardMonthlyAmount != null &&
              standardMonthlyAmount.isNotEmpty) {
            _amount = standardMonthlyAmount.trim();
          } else {
            _amount = "LKR 0,000.00";
          }
        }
        debugPrint("Using fallback amount: $_amount");
      }
    } catch (e) {
      debugPrint('Error in _loadPaymentDetails: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        debugPrint(
          "Finished loading payment details: amount=$_amount, name=$_customerName, account=$_accountNumber",
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 25,
                    vertical: 30,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFEAF8F0),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(14),
                        child: const Icon(
                          Icons.check,
                          color: Color(0xFF4CAF50),
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        t.payment_success_title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.payment_success_subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 30),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 20,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F8F8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                t.payment_details,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            _infoRow(
                              t.amount,
                              _amount.startsWith("LKR")
                                  ? _amount
                                  : "LKR $_amount",
                            ),
                            const SizedBox(height: 12),
                            _infoRow(
                              t.payment_status,
                              t.success,
                              isSuccess: true,
                            ),
                            const SizedBox(height: 12),
                            _infoRow(t.name, _customerName),
                            const SizedBox(height: 12),
                            _infoRow(t.account_number, _accountNumber),
                            const SizedBox(height: 12),
                            _infoRow(t.sender, "Unicon Finance"),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _generateAndDownloadPdf(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0xFF5DA2D5)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.download,
                            color: Color(0xFF5DA2D5),
                          ),
                          label: Text(
                            t.get_pdf_receipt,
                            style: const TextStyle(
                              color: Color(0xFF5DA2D5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 15),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DashboardScreen(),
                              ),
                              (_) => false,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5DA2D5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            t.done,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isSuccess = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        isSuccess
            ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFDFF5E3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: const [
                  Icon(Icons.check_circle, size: 16, color: Color(0xFF4CAF50)),
                  SizedBox(width: 5),
                  Text("Success", style: TextStyle(color: Color(0xFF4CAF50))),
                ],
              ),
            )
            : Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Future<void> _generateAndDownloadPdf(BuildContext context) async {
    final t = AppLocalizations.of(context)!;

    final pdf = pw.Document();

    String pdfAmount = _amount;
    if (!pdfAmount.startsWith("LKR")) {
      pdfAmount = "LKR $pdfAmount";
    }

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  t.payment_success_title,
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(t.payment_success_subtitle),
                pw.Divider(height: 30),
                pw.Text('${t.amount}: $pdfAmount'),
                pw.Text('${t.payment_status}: ${t.success}'),
                pw.Text('${t.name}: $_customerName'),
                pw.Text('${t.account_number}: $_accountNumber'),
                pw.Text('${t.sender}: Unicon Finance'),
                pw.SizedBox(height: 30),
                pw.Text(
                  'Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                ),
                pw.Text(
                  'Receipt ID: PAY-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
                ),
              ],
            ),
          );
        },
      ),
    );

    final Uint8List bytes = await pdf.save();

    await Printing.sharePdf(bytes: bytes, filename: 'receipt.pdf');
  }
}
