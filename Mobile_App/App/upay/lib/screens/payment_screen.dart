import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:upay/screens/receipt_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upay/services/secure_storage_service.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class PaymentAmountFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat('#,##0.00');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If the new value is empty, return as is
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Remove all non-digit characters
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: "",
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Convert to double (divide by 100 to handle decimals properly)
    double value = int.parse(digitsOnly) / 100;

    // Format with commas
    String formatted = _formatter.format(value);

    // Always place cursor at the end for simplicity
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _PaymentScreenState extends State<PaymentScreen> {
  final TextEditingController amountController = TextEditingController();
  bool _isHovered = false;
  bool _isPressed = false;
  String _displayAmount = "0.00"; // Default value
  bool _isProcessingPayment = false;
  
  // Firebase instance
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Payment gateway variables
  final TextEditingController cardNumberController = TextEditingController();
  final TextEditingController cardNameController = TextEditingController();
  final TextEditingController expiryController = TextEditingController();
  final TextEditingController cvvController = TextEditingController();
  bool isPaymentLoading = false;

  // User data
  String? _nic;
  String? _userId;
  String? _accountNumber;
  String? _customerId;
  Map<String, dynamic>? _installmentData;
  
  // Available balance
  double _availableBalance = 0;
  double _currentMonthInstallment = 0;

  // Stream subscription
  StreamSubscription<DocumentSnapshot>? _installmentSubscription;

  @override
  void initState() {
    super.initState();
    _loadMonthlyInstallmentAmount();
    _loadUserData();
  }

  // Load user data from secure storage
  Future<void> _loadUserData() async {
    try {
      // Get NIC from secure storage
      _nic = await SecureStorageService.getUserNic();
      
      if (_nic == null || _nic!.isEmpty) {
        debugPrint('NIC not found in secure storage');
        return;
      }
      
      debugPrint('Found NIC: $_nic');
      
      // Find user in customers collection using NIC
      final customerSnapshot = await _firestore
          .collection('customers')
          .where('nic', isEqualTo: _nic)
          .limit(1)
          .get();
      
      if (customerSnapshot.docs.isEmpty) {
        debugPrint('No customer found with NIC: $_nic');
        return;
      }
      
      // Get customer ID (document ID)
      _customerId = customerSnapshot.docs[0].id;
      debugPrint('Found customer ID: $_customerId');
      
      // Find finance document using customer ID
      final financeSnapshot = await _firestore
          .collection('finances')
          .where('customerId', isEqualTo: _customerId)
          .limit(1)
          .get();
      
      if (financeSnapshot.docs.isEmpty) {
        debugPrint('No finance record found for customer ID: $_customerId');
        return;
      }
      
      // Get account number from finance document
      _accountNumber = financeSnapshot.docs[0].data()['accountNumber'];
      debugPrint('Found account number: $_accountNumber');
      
      // Set user ID (same as customer ID in this case)
      _userId = _customerId;
      
      // Setup real-time listener for installment data
      if (_accountNumber != null) {
        _setupInstallmentListener();
      }
      
      setState(() {
        // Update the state with the loaded data
        _userId = _userId;
        _accountNumber = _accountNumber;
        _customerId = _customerId;
      });
      
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  // Setup real-time listener for installment data
  void _setupInstallmentListener() {
    if (_installmentSubscription != null) {
      _installmentSubscription!.cancel();
    }

    _installmentSubscription = _firestore
        .collection('installments')
        .doc(_accountNumber)
        .snapshots()
        .listen((documentSnapshot) {
          if (documentSnapshot.exists) {
            setState(() {
              _installmentData = documentSnapshot.data();
              _updateBalanceAndAmount();
            });
            debugPrint('Real-time installment data updated');
          }
        }, onError: (e) {
          debugPrint('Error in installment subscription: $e');
        });
  }

  void _updateBalanceAndAmount() {
    if (_installmentData != null) {
      // Update available balance
      _availableBalance = _installmentData!['balance'] ?? 0;
      
      // Get current month's installment amount
      String currentMonth = DateFormat('yyyy-MM').format(DateTime.now());
      double currentMonthAmount = 0;
      bool found = false;

      // Find the current month's installment in arrears
      if (_installmentData!.containsKey('arrears')) {
        for (var arrear in _installmentData!['arrears']) {
          if (arrear['month'].startsWith(currentMonth)) {
            if (arrear['status'] == 'due' || 
                arrear['status'] == 'overdue' || 
                arrear['status'] == 'partial') {
              currentMonthAmount = arrear['amountPayable'] is int 
                  ? (arrear['amountPayable'] as int).toDouble() 
                  : arrear['amountPayable'] as double;
              found = true;
              break;
            }
          }
        }
      }
      
      // If no current month installment found, use the monthly installment
      if (!found && _installmentData!.containsKey('monthlyInstallment')) {
        currentMonthAmount = _installmentData!['monthlyInstallment'].toDouble();
      }
      
      // Update current month installment
      _currentMonthInstallment = currentMonthAmount;
    }
  }

  // Load monthly installment amount from shared preferences (synced with dashboard)
  Future<void> _loadMonthlyInstallmentAmount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final amount = prefs.getString('monthly_installment_amount');
      
      if (amount != null && amount.isNotEmpty) {
        // Extract numeric value from "LKR X,XXX.XX" format
        String numericValue = amount.replaceAll(RegExp(r'[^0-9.,]'), '');
        
        // If it's coming from dashboard with LKR prefix, parse it correctly
        if (amount.toLowerCase().contains('lkr')) {
          try {
            // Clean the value by removing all non-numeric characters except decimal point
            numericValue = amount.replaceAll(RegExp(r'[^0-9.]'), '');
            double parsedAmount = double.parse(numericValue);
            numericValue = NumberFormat('#,##0.00').format(parsedAmount);
          } catch (e) {
            debugPrint('Error parsing monthly installment amount: $e');
          }
        }
        
        setState(() {
          _displayAmount = numericValue;
          // DO NOT update the text controller here
        });
        
        debugPrint('Loaded monthly installment amount from shared prefs: $_displayAmount');
      }
    } catch (e) {
      // Silent error handling for shared preferences
      debugPrint('Error loading monthly installment: $e');
    }
  }


  @override
  void dispose() {
    amountController.dispose();
    cardNumberController.dispose();
    cardNameController.dispose();
    expiryController.dispose();
    cvvController.dispose();
    
    // Cancel subscription to prevent memory leaks
    _installmentSubscription?.cancel();
    
    super.dispose();
  }

  // Process payment when user clicks Pay Now in the gateway
  Future<void> _processPayment(StateSetter setModalState) async {
    // Validate card information
    if (cardNumberController.text.isEmpty ||
        cardNameController.text.isEmpty ||
        expiryController.text.isEmpty ||
        cvvController.text.isEmpty) {
      return;
    }

    setModalState(() {
      isPaymentLoading = true;
    });

    // If user data is not loaded yet, try to load it again
    if (_userId == null || _accountNumber == null) {
      await _loadUserData();
      
      if (_userId == null || _accountNumber == null) {
        setModalState(() {
          isPaymentLoading = false;
        });
        return;
      }
    }

    // Get payment amount
    final cleanPaymentAmount = amountController.text.replaceAll(',', '');
    final paymentAmount = double.tryParse(cleanPaymentAmount) ?? 0;

    try {
      // Record payment in Firebase
      await _recordPaymentInFirebase(paymentAmount);
      
      // Simulate payment processing with delay
      await Future.delayed(const Duration(seconds: 2));

      // Close the payment gateway
      if (mounted) {
        Navigator.pop(context);

        // Navigate to receipt page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ReceiptScreen(),
          ),
        );
      }

    } catch (e) {
      debugPrint('Error processing payment: $e');

    } finally {
      if (mounted) {
        setModalState(() {
          isPaymentLoading = false;
        });
      }
    }
  }
  
  // Record payment in Firebase
  Future<void> _recordPaymentInFirebase(double paymentAmount) async {
    if (_userId == null || _accountNumber == null) {
      throw Exception('User ID or Account Number not found');
    }
    
    // Get current date in yyyy-MM-dd format
    final now = DateTime.now();
    final paymentDate = DateFormat('yyyy-MM-dd').format(now);
    
    // Get installment data
    final installmentDoc = await _firestore
        .collection('installments')
        .doc(_accountNumber)
        .get();
    
    if (!installmentDoc.exists) {
      throw Exception('Installment data not found for account: $_accountNumber');
    }
    
    // Get fresh installment data
    final installmentData = installmentDoc.data()!;
    
    // Calculate remaining balance
    double balance = installmentData['balance'] != null 
        ? (installmentData['balance'] is int 
            ? (installmentData['balance'] as int).toDouble() 
            : installmentData['balance'] as double) 
        : 0.0;
    
    // Process payment based on current installment status
    List<dynamic> arrears = List.from(installmentData['arrears']);
    List<dynamic> monthlyInstallments = List.from(installmentData['monthlyInstallments']);
    int installmentsPaid = installmentData['installmentsPaid'] ?? 0;
    int remainingInstallments = installmentData['remainingInstallments'] ?? 0;
    
    double remainingPayment = paymentAmount;
    bool isFullyPaid = false;
    
    // If payment amount is greater than or equal to the total balance, mark as fully paid
    if (remainingPayment >= balance) {
      // Mark all arrears as paid
      for (int i = 0; i < arrears.length; i++) {
        if (arrears[i]['status'] == 'pending' ||
            arrears[i]['status'] == 'due' ||
            arrears[i]['status'] == 'overdue' ||
            arrears[i]['status'] == 'partial') {
          
          String month = arrears[i]['month'];
          arrears[i]['status'] = 'paid';
          arrears[i]['amountPayable'] = 0.0;
          
          // Update the corresponding monthly installment
          for (int j = 0; j < monthlyInstallments.length; j++) {
            if (monthlyInstallments[j]['month'] == month) {
              // Use the standard amount for the full payment
              double standardAmount = 
                  arrears[i]['standardAmount'] != null 
                      ? (arrears[i]['standardAmount'] is int 
                          ? (arrears[i]['standardAmount'] as int).toDouble() 
                          : arrears[i]['standardAmount'] as double)
                      : (arrears[i]['amountPayable'] is int 
                          ? (arrears[i]['amountPayable'] as int).toDouble() 
                          : 0.0);
              monthlyInstallments[j]['amountPaid'] = standardAmount;
              monthlyInstallments[j]['paymentDate'] = paymentDate;
              monthlyInstallments[j]['status'] = 'paid';
              break;
            }
          }
        }
      }
      
      // Set values for fully paid loan
      int totalInstallments = installmentsPaid + remainingInstallments;
      installmentsPaid = totalInstallments;
      remainingInstallments = 0;
      balance = 0.0;
      isFullyPaid = true;
      
      debugPrint('Loan fully paid off');
    } else {
      // Process due/overdue/partial installments first
      List<Map<String, dynamic>> dueArrears = [];
      for (int i = 0; i < arrears.length; i++) {
        if (arrears[i]['status'] == 'due' || 
            arrears[i]['status'] == 'overdue' || 
            arrears[i]['status'] == 'partial') {
          dueArrears.add({'index': i, 'arrear': arrears[i]});
        }
      }
      
      // Sort by billing date (earliest first)
      dueArrears.sort((a, b) => 
        a['arrear']['billingDate'].compareTo(b['arrear']['billingDate'])
      );
      
      // Process due/overdue/partial installments
      for (var item in dueArrears) {
        if (remainingPayment <= 0) break;
        
        int idx = item['index'];
        double amountPayable = arrears[idx]['amountPayable'] is int 
            ? (arrears[idx]['amountPayable'] as int).toDouble() 
            : (arrears[idx]['amountPayable'] as double);
        String month = arrears[idx]['month'];
        
        // Store the standard amount if not already present
        if (!arrears[idx].containsKey('standardAmount')) {
          arrears[idx]['standardAmount'] = amountPayable;
        }
        
        double standardAmount = arrears[idx]['standardAmount'] is int 
            ? (arrears[idx]['standardAmount'] as int).toDouble() 
            : (arrears[idx]['standardAmount'] as double);
        
        debugPrint('Processing arrear for month: $month');
        debugPrint('Amount payable: $amountPayable');
        debugPrint('Standard amount: $standardAmount');
        
        if (remainingPayment >= amountPayable) {
          // Fully pay this installment
          arrears[idx]['status'] = 'paid';
          arrears[idx]['amountPayable'] = 0.0;
          
          // Update the corresponding monthly installment
          for (int j = 0; j < monthlyInstallments.length; j++) {
            if (monthlyInstallments[j]['month'] == month) {
              monthlyInstallments[j]['amountPaid'] = standardAmount;
              monthlyInstallments[j]['paymentDate'] = paymentDate;
              monthlyInstallments[j]['status'] = 'paid';
              break;
            }
          }
          
          remainingPayment -= amountPayable;
          installmentsPaid++;
          remainingInstallments--;
          balance -= amountPayable;
          
          debugPrint('Fully paid month: $month, remaining payment: $remainingPayment');
        } else {
          // Partial payment
          double newAmountPayable = amountPayable - remainingPayment;
          arrears[idx]['amountPayable'] = newAmountPayable;
          arrears[idx]['status'] = 'partial';
          
          // Update the corresponding monthly installment
          for (int j = 0; j < monthlyInstallments.length; j++) {
            if (monthlyInstallments[j]['month'] == month) {
              double currentPaid = monthlyInstallments[j]['amountPaid'] != null 
                  ? (monthlyInstallments[j]['amountPaid'] is int 
                      ? (monthlyInstallments[j]['amountPaid'] as int).toDouble() 
                      : monthlyInstallments[j]['amountPaid'] as double)
                  : 0.0;
              monthlyInstallments[j]['amountPaid'] = currentPaid + remainingPayment;
              monthlyInstallments[j]['paymentDate'] = paymentDate;
              monthlyInstallments[j]['status'] = 'partial';
              break;
            }
          }
          
          balance -= remainingPayment;
          remainingPayment = 0;
          
          debugPrint('Partially paid month: $month, new amount due: $newAmountPayable');
        }
      }
      
      // If there's still payment amount remaining, apply to pending installments
      if (remainingPayment > 0) {
        debugPrint('Excess payment: $remainingPayment - applying to future payments');
        
        // Get pending arrears in chronological order
        List<Map<String, dynamic>> pendingArrears = [];
        for (int i = 0; i < arrears.length; i++) {
          if (arrears[i]['status'] == 'pending') {
            pendingArrears.add({'index': i, 'arrear': arrears[i]});
          }
        }
        
        pendingArrears.sort((a, b) => 
          a['arrear']['billingDate'].compareTo(b['arrear']['billingDate'])
        );
        
        // Apply remaining payment to pending arrears
        for (var pendingItem in pendingArrears) {
          if (remainingPayment <= 0) break;
          
          int idx = pendingItem['index'];
          double amountPayable = arrears[idx]['amountPayable'] is int 
              ? (arrears[idx]['amountPayable'] as int).toDouble() 
              : (arrears[idx]['amountPayable'] as double);
          String month = arrears[idx]['month'];
          
          // Store the standard amount if not already present
          if (!arrears[idx].containsKey('standardAmount')) {
            arrears[idx]['standardAmount'] = amountPayable;
          }
          
          debugPrint('Processing pending month: $month, amount payable: $amountPayable');
          
          if (remainingPayment >= amountPayable) {
            // Fully pay this installment
            arrears[idx]['status'] = 'paid';
            arrears[idx]['amountPayable'] = 0.0;
            
            // Update monthly installment record
            for (int j = 0; j < monthlyInstallments.length; j++) {
              if (monthlyInstallments[j]['month'] == month) {
                double standardAmount = arrears[idx]['standardAmount'] is int 
                    ? (arrears[idx]['standardAmount'] as int).toDouble() 
                    : (arrears[idx]['standardAmount'] as double);
                monthlyInstallments[j]['amountPaid'] = standardAmount;
                monthlyInstallments[j]['paymentDate'] = paymentDate;
                monthlyInstallments[j]['status'] = 'paid';
                break;
              }
            }
            
            balance -= amountPayable;
            remainingPayment -= amountPayable;
            installmentsPaid++;
            remainingInstallments--;
            
            debugPrint('Fully paid pending month: $month, remaining: $remainingPayment');
          } else {
            // Partial payment for this pending installment
            double newAmountPayable = amountPayable - remainingPayment;
            arrears[idx]['amountPayable'] = newAmountPayable;
            arrears[idx]['status'] = 'partial'; // Change from pending to partial
            
            // Update monthly installment record
            for (int j = 0; j < monthlyInstallments.length; j++) {
              if (monthlyInstallments[j]['month'] == month) {
                double currentPaid = monthlyInstallments[j]['amountPaid'] != null 
                    ? (monthlyInstallments[j]['amountPaid'] is int 
                        ? (monthlyInstallments[j]['amountPaid'] as int).toDouble() 
                        : monthlyInstallments[j]['amountPaid'] as double)
                    : 0.0;
                monthlyInstallments[j]['amountPaid'] = currentPaid + remainingPayment;
                monthlyInstallments[j]['paymentDate'] = paymentDate;
                monthlyInstallments[j]['status'] = 'partial';
                break;
              }
            }
            
            balance -= remainingPayment;
            remainingPayment = 0;
            
            debugPrint('Partially paid pending month: $month, new amount due: $newAmountPayable');
          }
        }
        
        // If there's still remaining payment, reduce the balance
        if (remainingPayment > 0) {
          balance -= remainingPayment;
          debugPrint('Additional balance reduction: $remainingPayment');
        }
      }
      
      // If balance becomes zero or negative, mark as fully paid
      if (balance <= 0) {
        balance = 0.0;
        remainingInstallments = 0;
        int totalInstallments = installmentsPaid + remainingInstallments;
        installmentsPaid = totalInstallments;
        isFullyPaid = true;
        
        // Mark all remaining arrears as paid
        for (int i = 0; i < arrears.length; i++) {
          if (arrears[i]['status'] != 'paid') {
            arrears[i]['status'] = 'paid';
            arrears[i]['amountPayable'] = 0.0;
            
            String month = arrears[i]['month'];
            for (int j = 0; j < monthlyInstallments.length; j++) {
              if (monthlyInstallments[j]['month'] == month) {
                double standardAmount = arrears[i]['standardAmount'] != null 
                    ? (arrears[i]['standardAmount'] is int 
                        ? (arrears[i]['standardAmount'] as int).toDouble() 
                        : arrears[i]['standardAmount'] as double)
                    : (arrears[i]['amountPayable'] is int 
                        ? (arrears[i]['amountPayable'] as int).toDouble() 
                        : 0.0);
                monthlyInstallments[j]['status'] = 'paid';
                monthlyInstallments[j]['paymentDate'] = paymentDate;
                monthlyInstallments[j]['amountPaid'] = standardAmount;
                break;
              }
            }
          }
        }
        
        debugPrint('Balance reduced to zero - loan fully paid off');
      }
    }
    
    // Update next due date
    String nextDueDate = installmentData['nextDueDate'];
    if (!isFullyPaid) {
      // Find the next unpaid installment
      List<dynamic> sortedArrears = List.from(arrears);
      sortedArrears.sort((a, b) => a['billingDate'].compareTo(b['billingDate']));
      
      for (var arrear in sortedArrears) {
        if (arrear['status'] == 'due' || 
            arrear['status'] == 'overdue' || 
            arrear['status'] == 'pending' || 
            arrear['status'] == 'partial') {
          nextDueDate = arrear['billingDate'];
          break;
        }
      }
    }
    
    // Ensure balance is not negative
    if (balance < 0) balance = 0.0;
    
    debugPrint('New balance: $balance');
    debugPrint('Installments paid: $installmentsPaid, Remaining: $remainingInstallments');
    debugPrint('New next due date: $nextDueDate');
    
    // Update Firestore
    await _firestore.collection('installments').doc(_accountNumber).update({
      'arrears': arrears,
      'monthlyInstallments': monthlyInstallments,
      'installmentsPaid': installmentsPaid,
      'remainingInstallments': remainingInstallments,
      'balance': balance,
      'nextDueDate': nextDueDate,
      'lastPaymentDate': paymentDate,
      'lastPaymentAmount': paymentAmount,
      'lastUpdated': FieldValue.serverTimestamp()
    });
    
    // Add payment record
    await _firestore.collection('payments').add({
      'userId': _userId,
      'customerId': _customerId, // Add customer ID
      'accountNumber': _accountNumber,
      'amount': paymentAmount,
      'paymentDate': paymentDate,
      'paymentMethod': 'card',
      'cardHolderName': cardNameController.text,
      'cardNumber': cardNumberController.text.substring(cardNumberController.text.length - 4),  // Store only last 4 digits
      'createdAt': FieldValue.serverTimestamp(),
      'paymentType': isFullyPaid ? 'full' : 'regular',
    });
    
    // Update the local installment data
    _installmentData = {
      ...installmentData,
      'arrears': arrears,
      'monthlyInstallments': monthlyInstallments,
      'installmentsPaid': installmentsPaid,
      'remainingInstallments': remainingInstallments,
      'balance': balance,
      'nextDueDate': nextDueDate,
      'lastPaymentDate': paymentDate,
      'lastPaymentAmount': paymentAmount,
    };
    
    // Update balance variable for UI
    setState(() {
      _availableBalance = balance;
    });
    
    debugPrint('Payment recorded successfully');
  }

  void _showPaymentGateway(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.88,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // PayHere header - only showing logo now
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: const BoxDecoration(
                    color: Color(0xFF2B2D42),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    ),
                    height:50,
                  child: Center(
                    child: Image.asset(
                      'assets/images/payment/payhere_logo.png',
                      width: 100,
                      height: 80,
                    ),
                  ),
                ),
                
                // Payment details
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 5),
                          
                          // Order summary
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Order Summary',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Divider(),
                                const SizedBox(height: 5),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Monthly Installment'),
                                    Text(
                                      'LKR ${amountController.text.isEmpty ? "0.00" : amountController.text}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),

                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 28),
                          
                          // Card payment section
                          const Text(
                            'Pay with Card',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Card logos
                          Row(
                            children: [
                              Image.asset(
                                'assets/images/payment/visa.png',
                                height: 30,
                              ),
                              const SizedBox(width: 10),
                              Image.asset(
                                'assets/images/payment/mastercard.png',
                                height: 30,
                              ),
                              const SizedBox(width: 10),
                              Image.asset(
                                'assets/images/payment/amex.png',
                                height: 30,
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 28),
                          
                          // Card Number
                          _buildPaymentField(
                            controller: cardNumberController,
                            label: 'Card Number',
                            hint: 'XXXX XXXX XXXX XXXX',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(16),
                              CardNumberFormatter(),
                            ],
                          ),
                          
                          const SizedBox(height: 15),
                          
                          // Card Holder Name
                          _buildPaymentField(
                            controller: cardNameController,
                            label: 'Card Holder Name',
                            hint: 'Your Name',
                          ),
                          
                          const SizedBox(height: 15),
                          
                          // Expiry and CVV in a row
                          Row(
                            children: [
                              Expanded(
                                child: _buildPaymentField(
                                  controller: expiryController,
                                  label: 'Expiry Date',
                                  hint: 'MM/YY',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(4),
                                    ExpiryDateFormatter(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: _buildPaymentField(
                                  controller: cvvController,
                                  label: 'CVV',
                                  hint: 'XXX',
                                  keyboardType: TextInputType.number,
                                  obscureText: true,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(3), // Restrict to 3 digits for CVV
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 30),
                          
                          // Pay button - explicitly set text color to white
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isPaymentLoading 
                                ? null 
                                : () => _processPayment(setModalState),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2B2D42),
                                foregroundColor: Colors.white, // Explicitly setting text color
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: isPaymentLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.0,
                                      ),
                                    )
                                  : const Text(
                                      'Pay Now',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white, // Ensuring text is white
                                      ),
                                    ),
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Security note
                          Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.lock,
                                  size: 16,
                                  color: Colors.grey.shade700,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Payments are secure and encrypted',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Add extra padding at bottom for better scrolling
                          const SizedBox(height: 200),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaymentField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: Color(0xFF2B2D42),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final String today = DateFormat('dd - MM - yyyy').format(DateTime.now());

    // Format the balance to display as the monthly installment amount
    String formattedBalance = NumberFormat("#,##0.00").format(_availableBalance);
    
    // Format the current month installment
    String formattedCurrentMonthAmount = NumberFormat("#,##0.00").format(_currentMonthInstallment);
    
    // Get current month name for display
    String currentMonthName = DateFormat('MMMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFFEF7FF),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 46),
    
            // Custom AppBar
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
    
            const SizedBox(height: 30),
    
            // Top Info Section
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
            
            // Balance information - Now showing available balance
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.withAlpha((0.08 * 255).toInt()),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet, color: Colors.purple),
                    const SizedBox(width: 8),
                    Text(
                      "Available Balance: LKR $formattedBalance",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),
    
            // Total Amount Payable section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Total Amount Payable",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // Current month installment
                  Row(
                    children: [
                      const Icon(
                        Icons.payment_rounded,
                        color: Colors.purple,
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          "$currentMonthName Installment: LKR $formattedCurrentMonthAmount",
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 25),
                  
                  // Text field with only LKR showing and no default value in hint
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        PaymentAmountFormatter(),
                      ],
                      decoration: InputDecoration(
                        // Removed hint text
                        prefixIcon: const Icon(Icons.attach_money),
                        prefixText: "LKR ",
                        prefixStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        // Show hint text only when field is focused
                        hintStyle: TextStyle(
                          color: Colors.grey.withAlpha((0.5 * 255).toInt()),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    
            const SizedBox(height: 30),
    
            // Pay Button
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
                    if (!_isProcessingPayment) {
                      setState(() {
                        _isProcessingPayment = true;
                      });
                      
                      // If user data not loaded yet, try to load it first before showing payment gateway
                      if (_userId == null || _accountNumber == null) {
                        _loadUserData().then((_) {
                          if (!mounted) return;
                          
                          setState(() {
                            _isProcessingPayment = false;
                          });
                          
                          if (_userId != null && _accountNumber != null && mounted) {
                            // ignore: use_build_context_synchronously
                            _showPaymentGateway(context);
                          } else {
                            setState(() {
                              _isProcessingPayment = false;
                            });
                          }
                        });
                      } else {
                        // User data is already loaded, show payment gateway
                        setState(() {
                          _isProcessingPayment = false;
                        });
                        _showPaymentGateway(context);
                      }
                    }
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
                      child: _isProcessingPayment
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.0,
                            ),
                          )
                        : const Text(
                          "Pay",
                          style: TextStyle(
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
      ),
    );
  }
}

// Card number formatter - Format as "XXXX XXXX XXXX XXXX"
class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    String value = newValue.text.replaceAll(RegExp(r'\s+'), '');
    
    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < value.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write(' ');
      }
      buffer.write(value[i]);
    }

    String text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// Expiry date formatter - Format as "MM/YY"
class ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    String value = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    
    if (value.length > 2) {
      String month = value.substring(0, 2);
      String year = value.substring(2);
      return TextEditingValue(
        text: '$month/$year',
        selection: TextSelection.collapsed(offset: '$month/$year'.length),
      );
    } else {
      return TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }
}