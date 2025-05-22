import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:upay/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class LiabilityScreen extends StatefulWidget {
  const LiabilityScreen({super.key});

  @override
  State<LiabilityScreen> createState() => _LiabilityScreenState();
}

class _LiabilityScreenState extends State<LiabilityScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = true;
  String? _error;

  String firstName = '';
  String customerName = '';
  String vehicleNumber = '';
  String accountNumber = '';
  String loanAmount = '';
  String openingDate = '';
  String interestRate = '';
  String maturityDate = '';
  String balance = '';
  String nextInstallmentDate = '';
  String nextInstallmentAmount = '';
  String totalArrears = '';
  String remainingInstallments = '';
  String nic = '';
  bool isFullyPaid = false;

  static const String _cacheKey = 'liability_data_cache';
  static const String _cacheDateKey = 'liability_data_cache_date';
  static const int _cacheValidityHours = 6;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      if (await _loadFromCache()) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      await _loadLiabilityData();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error loading data: ${e.toString()}';
      });
    }
  }

  Future<bool> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedDataJson = prefs.getString(_cacheKey);
      final cacheDateString = prefs.getString(_cacheDateKey);

      if (cachedDataJson == null || cacheDateString == null) {
        return false;
      }

      final cacheDate = DateTime.parse(cacheDateString);
      final now = DateTime.now();
      final difference = now.difference(cacheDate);

      if (difference.inHours > _cacheValidityHours) {
        return false;
      }

      final Map<String, dynamic> cachedData = jsonDecode(cachedDataJson);

      setState(() {
        firstName = cachedData['firstName'] ?? '';
        customerName = cachedData['customerName'] ?? '';
        vehicleNumber = cachedData['vehicleNumber'] ?? '';
        accountNumber = cachedData['accountNumber'] ?? '';
        loanAmount = cachedData['loanAmount'] ?? '';
        openingDate = cachedData['openingDate'] ?? '';
        interestRate = cachedData['interestRate'] ?? '';
        maturityDate = cachedData['maturityDate'] ?? '';
        balance = cachedData['balance'] ?? '';
        nextInstallmentDate = cachedData['nextInstallmentDate'] ?? '';
        nextInstallmentAmount = cachedData['nextInstallmentAmount'] ?? '';
        totalArrears = cachedData['totalArrears'] ?? '';
        remainingInstallments = cachedData['remainingInstallments'] ?? '';
        nic = cachedData['nic'] ?? '';
        isFullyPaid = cachedData['isFullyPaid'] ?? false;
      });

      debugPrint("Loaded liability data from cache");
      return true;
    } catch (e) {
      debugPrint("Failed to load from cache: $e");
      return false;
    }
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final Map<String, dynamic> cacheData = {
        'firstName': firstName,
        'customerName': customerName,
        'vehicleNumber': vehicleNumber,
        'accountNumber': accountNumber,
        'loanAmount': loanAmount,
        'openingDate': openingDate,
        'interestRate': interestRate,
        'maturityDate': maturityDate,
        'balance': balance,
        'nextInstallmentDate': nextInstallmentDate,
        'nextInstallmentAmount': nextInstallmentAmount,
        'totalArrears': totalArrears,
        'remainingInstallments': remainingInstallments,
        'nic': nic,
        'isFullyPaid': isFullyPaid,
      };

      await prefs.setString(_cacheKey, jsonEncode(cacheData));
      await prefs.setString(_cacheDateKey, DateTime.now().toIso8601String());

      debugPrint("Saved liability data to cache");
    } catch (e) {
      debugPrint("Failed to save to cache: $e");
    }
  }

  Future<void> _loadLiabilityData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _error = 'You are not logged in. Please login again.';
        });
        return;
      }

      final userNic = await SecureStorageService.getUserNic();

      if (userNic == null || userNic.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = 'User NIC not found. Please login again.';
        });
        return;
      }

      setState(() {
        nic = userNic;
      });

      debugPrint("Loading liability data for NIC: $nic");
      debugPrint("User authenticated: ${user.uid}");

      debugPrint("Looking for installments with NIC: $nic");
      final installmentsNicSnapshot =
          await _firestore
              .collection('installments')
              .where('nic', isEqualTo: nic)
              .get();

      if (installmentsNicSnapshot.docs.isNotEmpty) {
        final accountNo =
            installmentsNicSnapshot.docs.first.data()['accountNumber'];
        if (accountNo != null) {
          debugPrint("Found installments with account number: $accountNo");
          await _loadDataByAccountNumber(accountNo.toString());
          return;
        }
      }

      debugPrint("DEBUG: Looking up customer with NIC: $nic");
      final customersSnapshot =
          await _firestore
              .collection('customers')
              .where('nic', isEqualTo: nic)
              .limit(1)
              .get();

      String customerId = '';

      if (customersSnapshot.docs.isNotEmpty) {
        final customerData = customersSnapshot.docs.first.data();
        customerId =
            customerData['customerId'] ??
            customerData['id'] ??
            customersSnapshot.docs.first.id;

        customerName =
            customerData['fullName'] ??
            customerData['name'] ??
            customerData['customerName'] ??
            'Not Available';

        firstName = customerName;
        debugPrint("Found customer with ID: $customerId, name: $customerName");
      } else {
        if (nic.length == 10) {
          String alternativeNic =
              nic.endsWith('v')
                  ? '${nic.substring(0, 9)}V'
                  : (nic.endsWith('V') ? '${nic.substring(0, 9)}v' : nic);

          if (alternativeNic != nic) {
            debugPrint("Trying alternative NIC format: $alternativeNic");
            final altSnapshot =
                await _firestore
                    .collection('customers')
                    .where('nic', isEqualTo: alternativeNic)
                    .limit(1)
                    .get();

            if (altSnapshot.docs.isNotEmpty) {
              final customerData = altSnapshot.docs.first.data();
              customerId =
                  customerData['customerId'] ??
                  customerData['id'] ??
                  altSnapshot.docs.first.id;

              customerName =
                  customerData['fullName'] ??
                  customerData['name'] ??
                  customerData['customerName'] ??
                  'Not Available';

              firstName = customerName;
              debugPrint("Found customer with alt NIC, ID: $customerId");
            }
          }
        }
      }

      if (customerId.isNotEmpty) {
        debugPrint("Looking for finances with customerId: $customerId");
        final financesSnapshot =
            await _firestore
                .collection('finances')
                .where('customerId', isEqualTo: customerId)
                .get();

        if (financesSnapshot.docs.isNotEmpty) {
          debugPrint("Found ${financesSnapshot.docs.length} finance records");
          final accountNo = financesSnapshot.docs.first.data()['accountNumber'];
          if (accountNo != null) {
            debugPrint("Found account number: $accountNo");
            await _loadDataByAccountNumber(accountNo.toString());
            return;
          }
        }
      }

      setState(() {
        _isLoading = false;
        _error = 'No liability data found for your account.';
      });
    } catch (e) {
      debugPrint("Failed to load liability data: $e");

      String errorMessage = 'Error loading liability data';
      if (e.toString().contains('permission-denied')) {
        errorMessage =
            'Permission denied: You don\'t have access to this data. Please contact support.';
      }

      setState(() {
        _isLoading = false;
        _error = errorMessage;
      });
    }
  }

  Future<void> _loadDataByAccountNumber(String accountNo) async {
    try {
      final financeQuery =
          await _firestore
              .collection('finances')
              .where('accountNumber', isEqualTo: accountNo)
              .limit(1)
              .get();

      if (financeQuery.docs.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = 'No finance records found for account: $accountNo';
        });
        return;
      }

      final installmentDocRef = _firestore
          .collection('installments')
          .doc(accountNo);
      final installmentDoc = await installmentDocRef.get();

      List<QueryDocumentSnapshot> installmentDocs = [];

      if (!installmentDoc.exists) {
        final installmentsQuery =
            await _firestore
                .collection('installments')
                .where('accountNumber', isEqualTo: accountNo)
                .get();

        if (installmentsQuery.docs.isNotEmpty) {
          installmentDocs = installmentsQuery.docs;
        }
      }

      if (firstName.isEmpty || customerName.isEmpty) {
        final customerId = financeQuery.docs.first.data()['customerId'];
        if (customerId != null) {
          final customerQuery =
              await _firestore.collection('customers').doc(customerId).get();

          if (customerQuery.exists) {
            final customerData = customerQuery.data();
            if (customerData != null) {
              customerName =
                  customerData['fullName'] ??
                  customerData['name'] ??
                  customerData['customerName'] ??
                  'Not Available';

              firstName = customerName;
              debugPrint("Found customer name: $customerName");
            }
          }
        }
      }

      final customerId = financeQuery.docs.first.data()['customerId'];
      final paymentsQuery =
          await _firestore
              .collection('payments')
              .where('customerId', isEqualTo: customerId)
              .where('accountNumber', isEqualTo: accountNo)
              .get();

      bool isFullyPaid = false;
      if (paymentsQuery.docs.isNotEmpty) {
        for (final paymentDoc in paymentsQuery.docs) {
          final paymentType =
              paymentDoc.data()['paymentType']?.toString().toLowerCase();
          if (paymentType == 'full') {
            isFullyPaid = true;
            break;
          }
        }
      }

      _processFinanceData(financeQuery.docs.first, isFullyPaid);

      if (installmentDoc.exists) {
        _processInstallmentDocData(installmentDoc, isFullyPaid);
      } else if (installmentDocs.isNotEmpty) {
        _processInstallmentData(installmentDocs, isFullyPaid);
      }

      await _saveToCache();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Failed to load data by account number: $e");
      setState(() {
        _isLoading = false;
        _error = 'Error loading finance details: ${e.toString()}';
      });
    }
  }

  void _processFinanceData(DocumentSnapshot doc, bool isFullyPaid) {
    try {
      final data = doc.data() as Map<String, dynamic>;

      final currencyFormatter = NumberFormat.currency(
        symbol: 'LKR ',
        decimalDigits: 2,
      );

      final dateFormatter = DateFormat('dd - MM - yyyy');

      setState(() {
        this.isFullyPaid = isFullyPaid;

        if (firstName.isEmpty || customerName.isEmpty) {
          if (data.containsKey('customerName')) {
            firstName = data['customerName'] ?? 'Not Available';
            customerName = firstName;
          } else if (data.containsKey('fullName')) {
            firstName = data['fullName'] ?? 'Not Available';
            customerName = firstName;
          }
        }

        accountNumber = data['accountNumber']?.toString() ?? 'Not Available';

        vehicleNumber = data['vehicleNumber'] ?? 'Not Available';

        if (data.containsKey('loanAmount')) {
          final rawAmount = data['loanAmount'];
          if (rawAmount is num) {
            loanAmount = currencyFormatter.format(rawAmount);
          } else {
            loanAmount = rawAmount?.toString() ?? 'Not Available';
          }
        }

        if (data.containsKey('openingDate')) {
          final rawDate = data['openingDate'];
          if (rawDate is Timestamp) {
            openingDate = dateFormatter.format(rawDate.toDate());
          } else if (rawDate is String) {
            try {
              final date = DateTime.parse(rawDate);
              openingDate = dateFormatter.format(date);
            } catch (_) {
              openingDate = rawDate;
            }
          } else {
            openingDate = 'Not Available';
          }
        }

        if (data.containsKey('interestRate')) {
          final rawRate = data['interestRate'];
          if (rawRate is num) {
            interestRate = '${rawRate.toStringAsFixed(2)}%';
          } else {
            interestRate = rawRate?.toString() ?? 'Not Available';
          }
        }

        if (isFullyPaid) {
          maturityDate = 'None';
        } else if (data.containsKey('maturityDate')) {
          final rawDate = data['maturityDate'];
          if (rawDate is Timestamp) {
            maturityDate = dateFormatter.format(rawDate.toDate());
          } else if (rawDate is String) {
            try {
              final date = DateTime.parse(rawDate);
              maturityDate = dateFormatter.format(date);
            } catch (_) {
              maturityDate = rawDate;
            }
          } else {
            maturityDate = 'Not Available';
          }
        }

        if (isFullyPaid) {
          nextInstallmentAmount = currencyFormatter.format(0);
        } else if (data.containsKey('monthlyInstallment')) {
          final rawAmount = data['monthlyInstallment'];
          if (rawAmount is num) {
            nextInstallmentAmount = currencyFormatter.format(rawAmount);
          } else {
            nextInstallmentAmount = rawAmount?.toString() ?? 'Not Available';
          }
        }
      });
    } catch (e) {
      debugPrint("Failed to process finance data: $e");
      setState(() {
        _isLoading = false;
        _error = 'Error processing finance data: ${e.toString()}';
      });
    }
  }

  void _processInstallmentDocData(DocumentSnapshot doc, bool isFullyPaid) {
    try {
      final data = doc.data() as Map<String, dynamic>;

      final currencyFormatter = NumberFormat.currency(
        symbol: 'LKR ',
        decimalDigits: 2,
      );

      final dateFormatter = DateFormat('dd - MM - yyyy');

      setState(() {
        if (isFullyPaid) {
          balance = currencyFormatter.format(0);
          maturityDate = 'None';
          nextInstallmentAmount = currencyFormatter.format(0);
        } else if (data.containsKey('balance')) {
          final rawBalance = data['balance'];
          if (rawBalance is num) {
            balance = currencyFormatter.format(rawBalance);
          } else {
            balance = rawBalance?.toString() ?? 'Not Available';
          }
        } else {
          balance = 'Not Available';
        }

        if (isFullyPaid) {
          remainingInstallments = "0";
        } else if (data.containsKey('remainingInstallments')) {
          final rawRemainingInstallments = data['remainingInstallments'];
          if (rawRemainingInstallments is num) {
            remainingInstallments = rawRemainingInstallments.toString();
          } else {
            remainingInstallments =
                rawRemainingInstallments?.toString() ?? 'Not Available';
          }
        } else {
          remainingInstallments = 'Not Available';
        }

        if (isFullyPaid) {
          nextInstallmentDate = 'None';
          totalArrears = currencyFormatter.format(0);
        } else {
          if (data.containsKey('nextDueDate')) {
            final rawDate = data['nextDueDate'];
            if (rawDate is String) {
              try {
                final date = DateTime.parse(rawDate);
                nextInstallmentDate = dateFormatter.format(date);
              } catch (_) {
                nextInstallmentDate = rawDate;
              }
            } else if (rawDate is Timestamp) {
              nextInstallmentDate = dateFormatter.format(rawDate.toDate());
            } else {
              nextInstallmentDate = 'Not Available';
            }
          }

          num totalArrearAmount = 0;
          if (data.containsKey('arrears')) {
            final arrears = data['arrears'] as List<dynamic>?;
            if (arrears != null) {
              final now = DateTime.now();
              final currentMonthYear =
                  "${now.year}-${now.month.toString().padLeft(2, '0')}";

              bool isCurrentMonthPaid = false;

              for (var arrear in arrears) {
                if (arrear is Map) {
                  String month = (arrear['month'] ?? '').toString();
                  String status =
                      (arrear['status'] ?? '').toString().toLowerCase();

                  if (month == currentMonthYear && status == 'paid') {
                    isCurrentMonthPaid = true;
                    break;
                  }
                }
              }

              for (var arrear in arrears) {
                if (arrear is Map) {
                  String month = (arrear['month'] ?? '').toString();
                  String status =
                      (arrear['status'] ?? '').toString().toLowerCase();
                  String billingDate = (arrear['billingDate'] ?? '').toString();

                  if (status == 'due' || status == 'overdue') {
                    try {
                      final dueDate = DateTime.parse(billingDate);
                      if (dueDate.isBefore(now)) {
                        final amount = arrear['amountPayable'];
                        if (amount is num) {
                          totalArrearAmount += amount;
                        }
                      }
                    } catch (_) {
                      if (month.compareTo(currentMonthYear) < 0 ||
                          (month == currentMonthYear && !isCurrentMonthPaid)) {
                        final amount = arrear['amountPayable'];
                        if (amount is num) {
                          totalArrearAmount += amount;
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          totalArrears = currencyFormatter.format(totalArrearAmount);
        }

        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Failed to process installment doc: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _processInstallmentData(
    List<QueryDocumentSnapshot> docs,
    bool isFullyPaid,
  ) {
    try {
      final dateFormatter = DateFormat('dd - MM - yyyy');

      final currencyFormatter = NumberFormat.currency(
        symbol: 'LKR ',
        decimalDigits: 2,
      );

      if (isFullyPaid) {
        setState(() {
          totalArrears = currencyFormatter.format(0);
          nextInstallmentDate = 'None';
          balance = currencyFormatter.format(0);
          remainingInstallments = "0";
          maturityDate = 'None';
          nextInstallmentAmount = currencyFormatter.format(0);
          _isLoading = false;
        });
        return;
      }

      if (docs.isNotEmpty) {
        final firstDoc = docs.first.data() as Map<String, dynamic>;

        if (firstDoc.containsKey('balance')) {
          final rawBalance = firstDoc['balance'];
          if (rawBalance is num) {
            balance = currencyFormatter.format(rawBalance);
          } else {
            balance = rawBalance?.toString() ?? 'Not Available';
          }
        }

        if (firstDoc.containsKey('remainingInstallments')) {
          remainingInstallments =
              firstDoc['remainingInstallments']?.toString() ?? 'Not Available';
        }

        if (firstDoc.containsKey('arrears')) {
          num totalArrearAmount = 0;
          final arrears = firstDoc['arrears'] as List<dynamic>?;

          if (arrears != null) {
            final now = DateTime.now();
            final currentMonthYear =
                "${now.year}-${now.month.toString().padLeft(2, '0')}";

            bool isCurrentMonthPaid = false;
            for (var arrear in arrears) {
              if (arrear is Map) {
                String month = (arrear['month'] ?? '').toString();
                String status =
                    (arrear['status'] ?? '').toString().toLowerCase();

                if (month == currentMonthYear && status == 'paid') {
                  isCurrentMonthPaid = true;
                  break;
                }
              }
            }

            for (var arrear in arrears) {
              if (arrear is Map) {
                String month = (arrear['month'] ?? '').toString();
                String status =
                    (arrear['status'] ?? '').toString().toLowerCase();
                String billingDate = (arrear['billingDate'] ?? '').toString();

                if (status == 'due' || status == 'overdue') {
                  try {
                    final dueDate = DateTime.parse(billingDate);
                    if (dueDate.isBefore(now)) {
                      final amount = arrear['amountPayable'];
                      if (amount is num) {
                        totalArrearAmount += amount;
                      }
                    }
                  } catch (_) {
                    if (month.compareTo(currentMonthYear) < 0 ||
                        (month == currentMonthYear && !isCurrentMonthPaid)) {
                      final amount = arrear['amountPayable'];
                      if (amount is num) {
                        totalArrearAmount += amount;
                      }
                    }
                  }
                }
              }
            }

            totalArrears = currencyFormatter.format(totalArrearAmount);
          }
        }

        if (firstDoc.containsKey('nextDueDate')) {
          final rawDate = firstDoc['nextDueDate'];
          if (rawDate is String) {
            try {
              final date = DateTime.parse(rawDate);
              nextInstallmentDate = dateFormatter.format(date);
            } catch (_) {
              nextInstallmentDate = rawDate;
            }
          } else if (rawDate is Timestamp) {
            nextInstallmentDate = dateFormatter.format(rawDate.toDate());
          }
        } else {
          if (firstDoc.containsKey('arrears')) {
            final arrears = firstDoc['arrears'] as List<dynamic>?;
            if (arrears != null) {
              final now = DateTime.now();
              DateTime? nextDate;

              for (var arrear in arrears) {
                if (arrear is Map &&
                    (arrear['status'] == 'due' ||
                        arrear['status'] == 'upcoming')) {
                  if (arrear.containsKey('billingDate')) {
                    try {
                      final dueDate = DateTime.parse(arrear['billingDate']);
                      if (dueDate.isAfter(now) &&
                          (nextDate == null || dueDate.isBefore(nextDate))) {
                        nextDate = dueDate;
                      }
                    } catch (_) {}
                  }
                }
              }

              if (nextDate != null) {
                nextInstallmentDate = dateFormatter.format(nextDate);
              }
            }
          }
        }
      }

      if (nextInstallmentDate.isEmpty ||
          nextInstallmentDate == 'Not Available') {
        final now = DateTime.now();

        final datedDocs =
            docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data.containsKey('billingDate');
            }).toList();

        if (datedDocs.isNotEmpty) {
          datedDocs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;

            final aDate = aData['billingDate'] as String;
            final bDate = bData['billingDate'] as String;

            return aDate.compareTo(bDate);
          });

          DateTime? nextDate;
          for (final doc in datedDocs) {
            final data = doc.data() as Map<String, dynamic>;
            try {
              final dueDate = DateTime.parse(data['billingDate']);
              if (dueDate.isAfter(now)) {
                nextDate = dueDate;
                break;
              }
            } catch (_) {}
          }

          if (nextDate != null) {
            nextInstallmentDate = dateFormatter.format(nextDate);
          }
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Failed to process installments: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _generateAndDownloadPDF({
    required String vehicleNumber,
    required String firstName,
    required Map<String, String> t,
    required Locale locale,
  }) async {
    final pdf = pw.Document();

    final sinhalaFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/pdf/Iskoola Pota Regular.ttf'),
    );
    final tamilFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/pdf/NotoSansTamil-Regular.ttf'),
    );

    late pw.Font? primaryFont;
    List<pw.Font> fallbackFonts = [];

    if (locale.languageCode == 'si') {
      primaryFont = sinhalaFont;
      fallbackFonts = [tamilFont];
    } else if (locale.languageCode == 'ta') {
      primaryFont = tamilFont;
      fallbackFonts = [sinhalaFont];
    } else {
      primaryFont = null;
      fallbackFonts = [sinhalaFont, tamilFont];
    }

    final logoImage = await imageFromAssetBundle(
      'assets/images/liability/letterhead.png',
    );

    pdf.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey, width: 1),
            ),
            padding: const pw.EdgeInsets.all(20),
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 24),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Image(logoImage, width: 554, height: 260),
                  ),
                  pw.SizedBox(height: 40),
                  pw.Text(
                    t['your_finance_details']!,
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      font: primaryFont,
                      fontFallback: fallbackFonts,
                    ),
                  ),
                  pw.SizedBox(height: 28),
                  _buildRowPdf(
                    t['first_name']!,
                    firstName,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),
                  _buildRowPdf(
                    t['vehicle_number']!,
                    vehicleNumber,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),
                  _buildRowPdf(
                    t['account_number']!,
                    accountNumber,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),
                  _buildRowPdf(
                    t['loan_amount']!,
                    loanAmount,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),
                  _buildRowPdf(
                    t['opening_date']!,
                    openingDate,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),
                  _buildRowPdf(
                    t['interest_rate']!,
                    interestRate,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),
                  _buildRowPdf(
                    t['maturity_date']!,
                    maturityDate,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),
                  _buildRowPdf(
                    t['balance']!,
                    balance,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),
                  _buildRowPdf(
                    t['next_installment_date']!,
                    nextInstallmentDate,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),
                  _buildRowPdf(
                    t['next_installment_amount']!,
                    nextInstallmentAmount,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),
                  _buildRowPdf(
                    t['total_arrears']!,
                    totalArrears,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),
                  _buildRowPdf(
                    t['remaining_installments']!,
                    remainingInstallments,
                    primaryFont,
                    fallbackFonts,
                  ),
                  pw.SizedBox(height: 8),

                  if (isFullyPaid) pw.SizedBox(height: 30),
                  if (isFullyPaid)
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(vertical: 15),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.green100,
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Center(
                        child: pw.Text(
                          'Your Finance Loan Settled',
                          style: pw.TextStyle(
                            color: PdfColors.green800,
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            font: primaryFont,
                            fontFallback: fallbackFonts,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'liability_details.pdf',
    );
  }

  pw.Widget _buildRowPdf(
    String label,
    String value,
    pw.Font? font,
    List<pw.Font> fallback,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 14,
              font: font,
              fontFallback: fallback,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 14,
              font: font,
              fontFallback: fallback,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 235, 245, 255),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _refreshData() {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _loadLiabilityData();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);

    final localizedStrings = {
      'your_finance_details': t.your_finance_details,
      'first_name': t.first_name,
      'vehicle_number': t.vehicle_number,
      'account_number': t.account_number,
      'loan_amount': t.loan_amount,
      'opening_date': t.opening_date,
      'interest_rate': t.interest_rate,
      'maturity_date': t.maturity_date,
      'balance': t.balance,
      'next_installment_date': t.next_installment_date,
      'next_installment_amount': t.next_installment_amount,
      'total_arrears': t.total_arrears,
      'remaining_installments': t.remaining_installments,
    };

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
                t.my_liability,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: _refreshData,
                    child: const Padding(
                      padding: EdgeInsets.all(10.0),
                      child: Icon(Icons.refresh, color: Colors.black54),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),

          if (_isLoading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text('Loading your liability details...'),
                  ],
                ),
              ),
            )
          else if (_error != null)
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
                            _isLoading = true;
                            _error = null;
                          });
                          _loadLiabilityData();
                        },
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
                                'assets/images/liability/liability.png',
                                width: 40,
                                height: 40,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      vehicleNumber,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      customerName,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap:
                                    () => _generateAndDownloadPDF(
                                      firstName: customerName,
                                      vehicleNumber: vehicleNumber,
                                      t: localizedStrings,
                                      locale: locale,
                                    ),
                                child: const Icon(
                                  Icons.print_rounded,
                                  size: 36,
                                  color: Color.fromARGB(255, 138, 125, 227),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (isFullyPaid)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Loan Fully Paid',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        const Divider(thickness: 1),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 25),
                      child: Column(
                        children: [
                          const SizedBox(height: 14),
                          _buildInfoRow(t.account_number, accountNumber),
                          _buildInfoRow(t.loan_amount, loanAmount),
                          _buildInfoRow(t.opening_date, openingDate),
                          _buildInfoRow(t.interest_rate, interestRate),
                          _buildInfoRow(t.maturity_date, maturityDate),
                          _buildInfoRow(t.balance, balance),
                          _buildInfoRow(
                            t.next_installment_date,
                            nextInstallmentDate,
                          ),
                          _buildInfoRow(
                            t.next_installment_amount,
                            nextInstallmentAmount,
                          ),
                          _buildInfoRow(t.total_arrears, totalArrears),
                          _buildInfoRow(
                            t.remaining_installments,
                            remainingInstallments,
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
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
