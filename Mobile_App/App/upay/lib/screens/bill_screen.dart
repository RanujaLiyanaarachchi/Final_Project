import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:upay/services/secure_storage_service.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BillScreen extends StatefulWidget {
  const BillScreen({super.key});

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _error;
  String _nic = '';
  String _accountNumber = '';
  String _customerName = 'Customer';

  String _totalArrears = 'LKR 0.00';
  String _standardMonthlyAmount = 'LKR 0,000.00';
  String _lastPaymentAmount = 'LKR 0.00';
  String _currentMonthBillDate = '00/00/0000';
  String _lastPaymentDate = '';

  static const String keyMonthlyInstallmentAmount =
      'monthly_installment_amount';
  static const String keyMonthlyInstallmentDate = 'monthly_installment_date';

  Timer? _syncTimer;

  late TabController _tabController;

  List<Map<String, dynamic>> _bills = [];
  Map<String, dynamic>? _currentMonthBillData;

  StreamSubscription? _installmentsSubscription;
  StreamSubscription? _paymentsSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    Future.wait([_loadSharedPreferences(), _loadBillData()]);

    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadSharedPreferences();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _installmentsSubscription?.cancel();
    _paymentsSubscription?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final amount = prefs.getString(keyMonthlyInstallmentAmount);
      final date = prefs.getString(keyMonthlyInstallmentDate);

      if (mounted) {
        setState(() {
          if (amount != null && amount.isNotEmpty) {
            _standardMonthlyAmount = amount;
          }

          if (date != null && date.isNotEmpty) {
            _currentMonthBillDate = date;
          }
        });
      }
    } catch (e) {
      debugPrint('error handling for shared preferences');
    }
  }

  Future<void> _saveToSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        keyMonthlyInstallmentAmount,
        _standardMonthlyAmount,
      );
      await prefs.setString(keyMonthlyInstallmentDate, _currentMonthBillDate);
    } catch (e) {
      debugPrint('error handling');
    }
  }

  Future<void> _loadBillData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _error = 'You are not logged in. Please login again.';
        });
        return;
      }

      final userNic = await SecureStorageService.getUserNic();
      if (userNic == null || userNic.isEmpty) {
        setState(() {
          _error = 'User NIC not found. Please login again.';
        });
        return;
      }

      setState(() {
        _nic = userNic;
      });

      final customersSnapshot =
          await _firestore
              .collection('customers')
              .where('nic', isEqualTo: _nic)
              .limit(1)
              .get();

      String customerId = '';

      if (customersSnapshot.docs.isNotEmpty) {
        final customerData = customersSnapshot.docs.first.data();
        customerId =
            customerData['customerId'] ??
            customerData['id'] ??
            customersSnapshot.docs.first.id;

        _customerName =
            customerData['fullName'] ??
            customerData['name'] ??
            customerData['customerName'] ??
            'Customer';
      }

      if (customerId.isNotEmpty) {
        final financesSnapshot =
            await _firestore
                .collection('finances')
                .where('customerId', isEqualTo: customerId)
                .limit(1)
                .get();

        if (financesSnapshot.docs.isNotEmpty) {
          final accountNo = financesSnapshot.docs.first.data()['accountNumber'];
          if (accountNo != null) {
            _accountNumber = accountNo.toString();
            _setupRealTimeUpdates(_accountNumber, customerId);
          } else {
            _setEmptyState();
          }
        } else {
          _setEmptyState();
        }
      } else {
        final installmentsNicSnapshot =
            await _firestore
                .collection('installments')
                .where('nic', isEqualTo: _nic)
                .limit(1)
                .get();

        if (installmentsNicSnapshot.docs.isNotEmpty) {
          final accountNo =
              installmentsNicSnapshot.docs.first.data()['accountNumber'];
          if (accountNo != null) {
            _accountNumber = accountNo.toString();
            _setupRealTimeUpdates(_accountNumber, '');
          } else {
            _setEmptyState();
          }
        } else {
          _setEmptyState();
        }
      }
    } catch (e) {
      _setEmptyState();
    }
  }

  void _setupRealTimeUpdates(String accountNumber, String customerId) {
    _fetchCurrentBillData(accountNumber);

    _installmentsSubscription = _firestore
        .collection('installments')
        .doc(accountNumber)
        .snapshots()
        .listen(
          (documentSnapshot) {
            if (documentSnapshot.exists) {
              _processInstallmentData(
                documentSnapshot.data(),
                accountNumber,
                customerId,
              );
            } else {
              _setEmptyState();
            }
          },
          onError: (e) {
            _setEmptyState();
          },
        );

    _setupPaymentsListener(accountNumber, customerId);
  }

  Future<void> _fetchCurrentBillData(String accountNumber) async {
    try {
      final doc =
          await _firestore.collection('installments').doc(accountNumber).get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        final currencyFormatter = NumberFormat.currency(
          symbol: 'LKR ',
          decimalDigits: 2,
        );

        if (data.containsKey('arrears') && data['arrears'] is List) {
          final arrears = data['arrears'] as List;

          for (var arrear in arrears) {
            if (arrear is Map &&
                arrear.containsKey('month') &&
                arrear['month'] == '2025-06') {
              final amountPayable = arrear['amountPayable'] ?? 9890;

              setState(() {
                _standardMonthlyAmount = currencyFormatter.format(
                  amountPayable,
                );
              });

              _saveToSharedPreferences();

              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('error handling');
    }
  }

  void _setupPaymentsListener(String accountNumber, String customerId) {
    Query paymentsQuery;

    if (accountNumber.isNotEmpty) {
      paymentsQuery = _firestore
          .collection('payments')
          .where('accountNumber', isEqualTo: accountNumber)
          .orderBy('createdAt', descending: true)
          .limit(20);
    } else if (customerId.isNotEmpty) {
      paymentsQuery = _firestore
          .collection('payments')
          .where('customerId', isEqualTo: customerId)
          .orderBy('createdAt', descending: true)
          .limit(20);
    } else {
      paymentsQuery = _firestore
          .collection('payments')
          .where('nic', isEqualTo: _nic)
          .orderBy('createdAt', descending: true)
          .limit(20);
    }

    _paymentsSubscription = paymentsQuery.snapshots().listen(
      (querySnapshot) {
        _processPaymentData(querySnapshot);
      },
      onError: (e) {
        setState(() {
          _lastPaymentAmount = 'LKR 0.00';
          _lastPaymentDate = '';
        });
      },
    );
  }

  void _setEmptyState() {
    if (!mounted) return;

    setState(() {
      _bills = [];
      _currentMonthBillData = null;

      _loadSharedPreferences().then((_) {
        if (_standardMonthlyAmount.isEmpty) {
          _standardMonthlyAmount = 'LKR 0,000.00';
        }
        if (_currentMonthBillDate.isEmpty) {
          _currentMonthBillDate = '00/00/0000';
        }
      });
    });
  }

  void _processInstallmentData(
    Map<String, dynamic>? data,
    String accountNumber,
    String customerId,
  ) {
    if (!mounted) return;

    try {
      final currencyFormatter = NumberFormat.currency(
        symbol: 'LKR ',
        decimalDigits: 2,
      );

      final dateFormatter = DateFormat('dd/MM/yyyy');

      List<Map<String, dynamic>> bills = [];
      num totalArrearsAmount = 0;
      Map<String, dynamic>? currentMonthBill;

      if (data != null) {
        final billingDay =
            data.containsKey('billingDay')
                ? int.tryParse(data['billingDay'].toString()) ?? 18
                : 18;

        final defaultBillingDate = DateTime(2025, 6, billingDay);
        final formattedDefaultBillingDate = dateFormatter.format(
          defaultBillingDate,
        );

        setState(() {
          _currentMonthBillDate = formattedDefaultBillingDate;
        });

        if (data.containsKey('arrears')) {
          final arrears = data['arrears'] as List<dynamic>?;

          if (arrears != null) {
            final yesterday = DateTime(2025, 6, DateTime.now().day - 1);
            final currentMonthStr = '2025-06';

            for (var arrear in arrears) {
              if (arrear is Map) {
                String status =
                    (arrear['status'] ?? '').toString().toLowerCase();
                String month = (arrear['month'] ?? '').toString();
                String billingDate = (arrear['billingDate'] ?? '').toString();

                num amountPayable = (arrear['amountPayable'] ?? 9890) as num;
                num paidAmount = (arrear['paidAmount'] ?? 0) as num;
                num remainingAmount = amountPayable - paidAmount;

                DateTime? billDate;
                try {
                  billDate = DateTime.parse(billingDate);
                } catch (_) {
                  try {
                    final parts = month.split('-');
                    if (parts.length == 2) {
                      billDate = DateTime(
                        int.parse(parts[0]),
                        int.parse(parts[1]),
                        billingDay,
                      );
                    }
                  } catch (_) {}
                }

                bool isCurrentMonth = month == currentMonthStr;

                if (isCurrentMonth) {
                  Map<String, dynamic> billItem = {
                    'month': month,
                    'status': status,
                    'billingDate': billDate ?? defaultBillingDate,
                    'amountPayable': amountPayable,
                    'paidAmount': paidAmount,
                    'remainingAmount': remainingAmount,
                    'formattedAmount': currencyFormatter.format(amountPayable),
                    'formattedPaid': currencyFormatter.format(paidAmount),
                    'formattedRemaining': currencyFormatter.format(
                      remainingAmount,
                    ),
                    'formattedDate':
                        billDate != null
                            ? dateFormatter.format(billDate)
                            : formattedDefaultBillingDate,
                    'isPaid': status == 'paid',
                    'isPartiallyPaid':
                        status == 'partially_paid' ||
                        status == 'partial' ||
                        (paidAmount > 0 && paidAmount < amountPayable),
                    'isOverdue':
                        status == 'overdue' ||
                        (status == 'due' &&
                            billDate != null &&
                            billDate.isBefore(yesterday)),
                    'isCurrentMonth': true,
                  };

                  bills.add(billItem);
                  currentMonthBill = billItem;

                  setState(() {
                    _standardMonthlyAmount = currencyFormatter.format(
                      amountPayable,
                    );
                  });
                  _saveToSharedPreferences();
                }

                bool isPastDue = false;

                if (month.contains('-')) {
                  try {
                    final parts = month.split('-');
                    if (parts.length == 2) {
                      final year = int.parse(parts[0]);
                      final monthNum = int.parse(parts[1]);

                      if (year < 2025 || (year == 2025 && monthNum < 6)) {
                        isPastDue = true;
                      }
                    }
                  } catch (_) {}
                }

                if (isPastDue && status != 'paid' && remainingAmount > 0) {
                  totalArrearsAmount += remainingAmount;
                }
              }
            }

            if (currentMonthBill == null) {
              final defaultMonthlyAmount = 0000;

              currentMonthBill = {
                'month': currentMonthStr,
                'status': 'partial',
                'billingDate': defaultBillingDate,
                'amountPayable': defaultMonthlyAmount,
                'paidAmount': 0,
                'remainingAmount': defaultMonthlyAmount,
                'formattedAmount': currencyFormatter.format(
                  defaultMonthlyAmount,
                ),
                'formattedPaid': currencyFormatter.format(0),
                'formattedRemaining': currencyFormatter.format(
                  defaultMonthlyAmount,
                ),
                'formattedDate': formattedDefaultBillingDate,
                'isPaid': false,
                'isPartiallyPaid': false,
                'isOverdue': false,
                'isCurrentMonth': true,
              };

              bills.add(currentMonthBill);

              setState(() {
                _standardMonthlyAmount = currencyFormatter.format(
                  defaultMonthlyAmount,
                );
              });
              _saveToSharedPreferences();
            }

            setState(() {
              _totalArrears = currencyFormatter.format(totalArrearsAmount);
              _bills = bills;

              if (currentMonthBill != null) {
                _currentMonthBillData = currentMonthBill;
              }
            });
          } else {
            _handleEmptyArrearsWithStandardAmount(
              data,
              currencyFormatter,
              dateFormatter,
            );
          }
        } else {
          _handleEmptyArrearsWithStandardAmount(
            data,
            currencyFormatter,
            dateFormatter,
          );
        }
      } else {
        _setEmptyState();
      }
    } catch (_) {
      _setEmptyState();
    }
  }

  void _handleEmptyArrearsWithStandardAmount(
    Map<String, dynamic> data,
    NumberFormat currencyFormatter,
    DateFormat dateFormatter,
  ) {
    final billingDate = DateTime(2025, 6, 18);
    final standardAmount = _parseAmount(data['standardAmount'] ?? 9890);
    final currentMonthStr = '2025-06';
    final formattedDate = dateFormatter.format(billingDate);

    final currentMonthBill = {
      'month': currentMonthStr,
      'status': 'partial',
      'billingDate': billingDate,
      'amountPayable': standardAmount,
      'paidAmount': 0,
      'remainingAmount': standardAmount,
      'formattedAmount': currencyFormatter.format(standardAmount),
      'formattedPaid': currencyFormatter.format(0),
      'formattedRemaining': currencyFormatter.format(standardAmount),
      'formattedDate': formattedDate,
      'isPaid': false,
      'isPartiallyPaid': false,
      'isOverdue': false,
      'isCurrentMonth': true,
    };

    setState(() {
      _currentMonthBillDate = formattedDate;
      _standardMonthlyAmount = currencyFormatter.format(standardAmount);
      _totalArrears = 'LKR 0.00';

      _currentMonthBillData = currentMonthBill;

      _bills = [currentMonthBill];

      _saveToSharedPreferences();
    });
  }

  double _parseAmount(dynamic amount) {
    if (amount is num) {
      return amount.toDouble();
    } else if (amount is String) {
      try {
        String cleanedString = amount.replaceAll(RegExp(r'[^0-9.]'), '');
        return double.parse(cleanedString);
      } catch (_) {
        return 0000.00;
      }
    }
    return 0000.00;
  }

  void _processPaymentData(QuerySnapshot querySnapshot) {
    if (!mounted) return;

    try {
      final currencyFormatter = NumberFormat.currency(
        symbol: 'LKR ',
        decimalDigits: 2,
      );

      final dateFormatter = DateFormat('dd/MM/yyyy');

      if (querySnapshot.docs.isNotEmpty) {
        final payments =
            querySnapshot.docs.map((doc) {
              return doc.data() as Map<String, dynamic>;
            }).toList();

        payments.sort((a, b) {
          final createdAtA = a['createdAt'] as Timestamp?;
          final createdAtB = b['createdAt'] as Timestamp?;

          if (createdAtA != null && createdAtB != null) {
            return createdAtB.compareTo(createdAtA);
          }

          final dateA = _extractPaymentDate(a);
          final dateB = _extractPaymentDate(b);

          if (dateA != null && dateB != null) {
            return dateB.compareTo(dateA);
          }

          if (dateA != null) return -1;
          if (dateB != null) return 1;

          return 0;
        });

        if (payments.isNotEmpty) {
          final payment = payments.first;

          dynamic amount = payment['paymentAmount'] ?? payment['amount'] ?? 0;

          num paymentAmount;
          if (amount is num) {
            paymentAmount = amount;
          } else {
            try {
              paymentAmount = num.parse(amount.toString());
            } catch (_) {
              paymentAmount = 0;
            }
          }

          String formattedDate = 'N/A';

          if (payment.containsKey('paymentDate')) {
            final paymentDate = payment['paymentDate'];
            if (paymentDate is String) {
              try {
                final date = DateTime.parse(paymentDate);
                formattedDate = dateFormatter.format(date);
              } catch (e) {
                formattedDate = paymentDate;
              }
            } else if (paymentDate is Timestamp) {
              formattedDate = dateFormatter.format(paymentDate.toDate());
            }
          } else if (payment.containsKey('createdAt')) {
            final createdAt = payment['createdAt'];
            if (createdAt is Timestamp) {
              formattedDate = dateFormatter.format(createdAt.toDate());
            }
          } else {
            final dateTime = _extractPaymentDate(payment);
            if (dateTime != null) {
              formattedDate = dateFormatter.format(dateTime);
            }
          }

          setState(() {
            _lastPaymentAmount = currencyFormatter.format(paymentAmount);
            _lastPaymentDate = formattedDate;

            if (_currentMonthBillData != null) {
              final paymentDate = _extractPaymentDate(payment);

              if (paymentDate != null &&
                  paymentDate.year == 2025 &&
                  paymentDate.month == 6) {
                final amountPayable =
                    _currentMonthBillData!['amountPayable'] as num;
                final paidAmount =
                    (_currentMonthBillData!['paidAmount'] as num) +
                    paymentAmount;

                _currentMonthBillData!['paidAmount'] = paidAmount;
                _currentMonthBillData!['remainingAmount'] =
                    amountPayable > paidAmount ? amountPayable - paidAmount : 0;
                _currentMonthBillData!['formattedPaid'] = currencyFormatter
                    .format(paidAmount);
                _currentMonthBillData!['formattedRemaining'] = currencyFormatter
                    .format(
                      amountPayable > paidAmount
                          ? amountPayable - paidAmount
                          : 0,
                    );

                if (paidAmount >= amountPayable) {
                  _currentMonthBillData!['status'] = 'paid';
                  _currentMonthBillData!['isPaid'] = true;
                  _currentMonthBillData!['isPartiallyPaid'] = false;
                } else if (paidAmount > 0) {
                  _currentMonthBillData!['status'] = 'partially_paid';
                  _currentMonthBillData!['isPaid'] = false;
                  _currentMonthBillData!['isPartiallyPaid'] = true;
                }
              }
            }
          });
        } else {
          setState(() {
            _lastPaymentAmount = 'LKR 0.00';
            _lastPaymentDate = 'No payments';
          });
        }
      } else {
        setState(() {
          _lastPaymentAmount = 'LKR 0.00';
          _lastPaymentDate = 'No payments';
        });
      }
    } catch (_) {
      setState(() {
        _lastPaymentAmount = 'LKR 0.00';
        _lastPaymentDate = 'Error loading';
      });
    }
  }

  DateTime? _extractPaymentDate(Map<String, dynamic> payment) {
    final dateFields = [
      'paymentDate',
      'date',
      'timestamp',
      'createdAt',
      'created_at',
      'updatedAt',
      'updated_at',
    ];

    for (final field in dateFields) {
      if (payment.containsKey(field)) {
        final value = payment[field];

        if (value is Timestamp) {
          return value.toDate();
        } else if (value is String && value.isNotEmpty) {
          try {
            return DateTime.parse(value);
          } catch (_) {
            if (value.contains('/')) {
              try {
                final parts = value.split('/');
                if (parts.length == 3) {
                  return DateTime(
                    int.parse(parts[2]),
                    int.parse(parts[1]),
                    int.parse(parts[0]),
                  );
                }
              } catch (_) {}
            }
          }
        }
      }
    }

    return null;
  }

  Future<void> _generateAndDownloadBillPDF(Map<String, dynamic> bill) async {
    final pdf = pw.Document();

    try {
      final locale = Localizations.localeOf(context);

      final sinhalaFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/pdf/Iskoola Pota Regular.ttf'),
      );
      final tamilFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/pdf/NotoSansTamil-Regular.ttf'),
      );

      List<pw.Font> fallbackFonts = [];

      if (locale.languageCode == 'si') {
        fallbackFonts = [sinhalaFont, tamilFont];
      } else if (locale.languageCode == 'ta') {
        fallbackFonts = [tamilFont, sinhalaFont];
      } else {
        fallbackFonts = [sinhalaFont, tamilFont];
      }

      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            fontFallback: fallbackFonts,
          ),
          build: (pw.Context context) => [],
        ),
      );

      final logoImage = await imageFromAssetBundle(
        'assets/images/liability/letterhead.png',
      );

      final dateFormatter = DateFormat('dd MMMM yyyy');
      final billDate = bill['billingDate'] as DateTime?;
      final formattedBillDate =
          billDate != null
              ? dateFormatter.format(billDate)
              : bill['formattedDate'];

      pdf.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey, width: 1),
              ),
              padding: const pw.EdgeInsets.all(20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Image(logoImage, width: 554, height: 260),
                  ),
                  pw.SizedBox(height: 40),
                  pw.Center(
                    child: pw.Text(
                      'INVOICE / BILL',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 30),

                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Bill To:',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            pw.SizedBox(height: 5),
                            pw.Text(
                              _customerName,
                              style: const pw.TextStyle(fontSize: 14),
                            ),
                            pw.Text(
                              'Account: $_accountNumber',
                              style: const pw.TextStyle(fontSize: 14),
                            ),
                            pw.Text(
                              'NIC: $_nic',
                              style: const pw.TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              'Bill Date:',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            pw.SizedBox(height: 5),
                            pw.Text(
                              formattedBillDate,
                              style: const pw.TextStyle(fontSize: 14),
                            ),
                            pw.Text(
                              'Bill Month: ${bill['month']}',
                              style: const pw.TextStyle(fontSize: 14),
                            ),
                            pw.Text(
                              'Status: ${bill['status'].toUpperCase()}',
                              style: pw.TextStyle(
                                fontSize: 14,
                                color:
                                    bill['isPaid']
                                        ? PdfColors.green
                                        : (bill['isOverdue']
                                            ? PdfColors.red
                                            : PdfColors.black),
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 30),

                  pw.Container(
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    padding: const pw.EdgeInsets.all(15),
                    child: pw.Column(
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Description',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Text(
                              'Amount',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        pw.Divider(),
                        pw.SizedBox(height: 10),

                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Monthly Installment'),
                            pw.Text(bill['formattedAmount']),
                          ],
                        ),

                        if (bill['isPartiallyPaid']) ...[
                          pw.SizedBox(height: 10),
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Amount Paid'),
                              pw.Text('(${bill['formattedPaid']})'),
                            ],
                          ),
                          pw.SizedBox(height: 10),
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'Balance Due',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                NumberFormat.currency(
                                  symbol: 'LKR ',
                                  decimalDigits: 2,
                                ).format(bill['remainingAmount']),
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],

                        if (bill['isPaid']) ...[
                          pw.SizedBox(height: 20),
                          pw.Container(
                            width: double.infinity,
                            padding: const pw.EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.green100,
                              borderRadius: pw.BorderRadius.circular(5),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                'PAID IN FULL',
                                style: pw.TextStyle(
                                  color: PdfColors.green800,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],

                        if (bill['isOverdue'] && !bill['isPaid']) ...[
                          pw.SizedBox(height: 20),
                          pw.Container(
                            width: double.infinity,
                            padding: const pw.EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.red100,
                              borderRadius: pw.BorderRadius.circular(5),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                'PAYMENT OVERDUE',
                                style: pw.TextStyle(
                                  color: PdfColors.red800,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 30),

                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(15),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Payment Information:',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        pw.SizedBox(height: 10),
                        pw.Text(
                          'Please make your payment at our nearest branch.',
                        ),
                        pw.Text('Account Number: $_accountNumber'),
                        pw.SizedBox(height: 15),
                        pw.Text(
                          'Payment Hotline: 025 2236432',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                  pw.Spacer(),
                  pw.Center(
                    child: pw.Text(
                      'Thank you for your business',
                      style: const pw.TextStyle(
                        color: PdfColors.grey700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      await Printing.layoutPdf(onLayout: (format) => pdf.save());
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'bill_${bill['month']}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to generate bill PDF. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildCard({
    required String title,
    String? date,
    required String amount,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withAlpha((0.8 * 255).round())],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha((0.3 * 255).round()),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if (date != null && date.isNotEmpty && date != 'N/A')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(51),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      date,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 30),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                amount,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillItem(Map<String, dynamic> bill) {
    final isPartiallyPaid = bill['isPartiallyPaid'];

    String amountDisplay;
    if (isPartiallyPaid) {
      amountDisplay = bill['formattedRemaining'];
    } else {
      amountDisplay = bill['formattedAmount'];
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.purple, width: 1.5),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _generateAndDownloadBillPDF(bill),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.purple.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    color: Colors.purple,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Bill: ${bill['month']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple.withAlpha(26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Current',
                              style: TextStyle(
                                color: Colors.purple,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Due Date: ${bill['formattedDate']}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        amountDisplay,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withAlpha(26),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.download,
                      color: Colors.purple,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final String today = DateFormat('dd/MM/yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFFEF7FF),
      body: Column(
        children: [
          const SizedBox(height: 80),
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
                t.bill_payments,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 60,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, color: Colors.red),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _error = null;
                          });
                          _loadBillData();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C17A6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 239, 247, 255),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/images/bill/bill.png',
                                width: 40,
                                height: 40,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.bill_payments,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      today,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(18),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicator: BoxDecoration(
                              color: const Color(0xFF6C17A6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            labelPadding: EdgeInsets.zero,
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.black54,
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            unselectedLabelStyle: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                            tabs: [
                              Tab(text: t.bill_summary),
                              Tab(text: t.bills),
                            ],
                            dividerColor: Colors.transparent,
                          ),
                        ),

                        const SizedBox(height: 10),
                        const Divider(thickness: 1),
                      ],
                    ),
                  ),

                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 25),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              _buildCard(
                                title: t.total_arrears,
                                date: null,
                                amount: _totalArrears,
                                color: const Color(0xFFAA4A4A),
                              ),

                              _buildCard(
                                title: t.monthly_bill,
                                date: _currentMonthBillDate,
                                amount: _standardMonthlyAmount,
                                color: const Color(0xFF626EB2),
                              ),

                              _buildCard(
                                title: t.last_payment_amount,
                                date:
                                    _lastPaymentDate.isEmpty
                                        ? 'N/A'
                                        : _lastPaymentDate,
                                amount: _lastPaymentAmount,
                                color: const Color(0xFF4F5773),
                              ),
                            ],
                          ),
                        ),

                        _bills.isEmpty
                            ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.receipt_long,
                                    size: 70,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No bills available',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                            : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 25,
                                vertical: 16,
                              ),
                              itemCount: _bills.length,
                              itemBuilder: (context, index) {
                                return _buildBillItem(_bills[index]);
                              },
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
